
class EstimateEntry < ActiveRecord::Base
  include Redmine::SafeAttributes
  # could have used polymorphic association
  # project association here allows easy loading of time entries at project level with one database trip
  belongs_to :project
  belongs_to :issue
  belongs_to :user
  belongs_to :activity, :class_name => 'TimeEntryActivity'

  attr_protected :project_id, :user_id, :tyear, :tmonth, :tweek # ":project_id," added

  acts_as_customizable

  #default_scope :order => 'spent_on ASC'

  validates_presence_of :user_id, :activity_id, :project_id, :hours, :spent_on
  validates_presence_of :issue_id, :if => lambda { Setting.timelog_required_fields.include?('issue_id') }
  validates_presence_of :comments, :if => lambda { Setting.timelog_required_fields.include?('comments') }
  validates_numericality_of :hours, :allow_nil => true, :message => :invalid
  validates_length_of :comments, :maximum => 1024, :allow_nil => true
  validates :spent_on, :date => true
  before_validation :set_project_if_nil
  validate :validate_time_entry

  scope :visible, lambda {|*args|
    joins(:project).
    where(EstimateEntry.visible_condition(args.shift || User.current, *args)) # changed
  }
  scope :left_join_issue, lambda {
    joins("LEFT OUTER JOIN #{Issue.table_name} ON #{Issue.table_name}.id = #{EstimateEntry.table_name}.issue_id") # changed
  }
  scope :on_issue, lambda {|issue|
    joins(:issue).
    where("#{Issue.table_name}.root_id = #{issue.root_id} AND #{Issue.table_name}.lft >= #{issue.lft} AND #{Issue.table_name}.rgt <= #{issue.rgt}")
  }

  safe_attributes 'hours', 'comments', 'project_id', 'issue_id', 'activity_id', 'spent_on', 'custom_field_values', 'custom_fields'

  # Returns a SQL conditions string used to find all time entries visible by the specified user
  def self.visible_condition(user, options={})
    Project.allowed_to_condition(user, :view_time_entries, options) do |role, user|
      if role.time_entries_visibility == 'all'
        nil
      elsif role.time_entries_visibility == 'own' && user.id && user.logged?
        "#{table_name}.user_id = #{user.id}"
      else
        '1=0'
      end
    end
  end

  # Returns true if user or current user is allowed to view the time entry
  def visible?(user=nil)
    (user || User.current).allowed_to?(:view_time_entries, self.project) do |role, user|
      if role.time_entries_visibility == 'all'
        true
      elsif role.time_entries_visibility == 'own'
        self.user == user
      else
        false
      end
    end
  end

  def initialize(attributes=nil, *args)
    super
    if new_record? && self.activity.nil?
      if default_activity = TimeEntryActivity.default
        self.activity_id = default_activity.id
      end
      self.hours = nil if hours == 0
    end
  end

  def safe_attributes=(attrs, user=User.current)
    attrs = super
    if !new_record? && issue && issue.project_id != project_id
      if user.allowed_to?(:log_time, issue.project)
        self.project_id = issue.project_id
      end
    end
    attrs
  end

=begin
  def safe_attributes=(attrs, user=User.current)
    if attrs
      attrs = super(attrs)
      if issue_id_changed? && issue
        if issue.visible?(user) && user.allowed_to?(:log_time, issue.project)
          if attrs[:project_id].blank? && issue.project_id != project_id
            self.project_id = issue.project_id
          end
          @invalid_issue_id = nil
        else
          @invalid_issue_id = issue_id
        end
      end
    end
    attrs
  end
=end

  def set_project_if_nil
    self.project = issue.project if issue && project.nil?
  end

  def validate_time_entry
    errors.add :hours, :invalid if hours && (hours < 0 || hours >= 1000)
    errors.add :project_id, :invalid if project.nil?
    errors.add :issue_id, :invalid if (issue_id && !issue) || (issue && project!=issue.project) # changed || @invalid_issue_id
    errors.add :activity_id, :inclusion if activity_id_changed? && project && !project.activities.include?(activity)
  end

  def hours=(h)
    write_attribute :hours, (h.is_a?(String) ? (h.to_hours || h) : h)
  end

  def hours
    h = read_attribute(:hours)
    if h.is_a?(Float)
      h.round(2)
    else
      h
    end
  end

  # tyear, tmonth, tweek assigned where setting spent_on attributes
  # these attributes make time aggregations easier
  def spent_on=(date)
    super
    self.tyear = spent_on ? spent_on.year : nil
    self.tmonth = spent_on ? spent_on.month : nil
    self.tweek = spent_on ? Date.civil(spent_on.year, spent_on.month, spent_on.day).cweek : nil
  end

  # Returns true if the time entry can be edited by usr, otherwise false
  def editable_by?(usr)
    visible?(usr) && (
      (usr == user && usr.allowed_to?(:edit_own_time_entries, project)) || usr.allowed_to?(:edit_time_entries, project)
    )
  end

=begin
  # Returns the custom_field_values that can be edited by the given user
  def editable_custom_field_values(user=nil)
    visible_custom_field_values
  end

  # Returns the custom fields that can be edited by the given user
  def editable_custom_fields(user=nil)
    editable_custom_field_values(user).map(&:custom_field).uniq
  end
=end

end
