require_dependency 'issue_query'

module IssueQueryPatch
  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)

    base.class_eval do
      unloadable
      alias_method_chain :available_columns, :patch
      alias_method_chain :initialize_available_filters, :patch

      self.available_columns.concat([
		    QueryColumn.new(:total_estimate_hours, :sortable => "COALESCE((SELECT SUM(hours) FROM #{EstimateEntry.table_name} WHERE #{EstimateEntry.table_name}.issue_id = #{Issue.table_name}.id), 0)"),
        QueryColumn.new(:total_accepted_estimate_hours, :sortable => "COALESCE((SELECT SUM(hours) FROM #{EstimateEntry.table_name} WHERE #{EstimateEntry.table_name}.issue_id = #{Issue.table_name}.id), 0)")
      ])
    end
  end

  module InstanceMethods

    def initialize_available_filters_with_patch
      # взято из версии 3.х.х
      add_available_filter "status_id",
                           :type => :list_status, :values => lambda { issue_statuses_values }

      add_available_filter("project_id",
                           :type => :list, :values => lambda { project_values }
      ) if project.nil?

      add_available_filter "tracker_id",
                           :type => :list, :values => trackers.collect{|s| [s.name, s.id.to_s] }

      add_available_filter "priority_id",
                           :type => :list, :values => IssuePriority.all.collect{|s| [s.name, s.id.to_s] }

      add_available_filter("author_id",
                           :type => :list, :values => lambda { author_values }
      )

      add_available_filter("assigned_to_id",
                           :type => :list_optional, :values => lambda { assigned_to_values }
      )

      add_available_filter("member_of_group",
                           :type => :list_optional, :values => lambda { Group.givable.visible.collect {|g| [g.name, g.id.to_s] } }
      )

      add_available_filter("assigned_to_role",
                           :type => :list_optional, :values => lambda { Role.givable.collect {|r| [r.name, r.id.to_s] } }
      )

      add_available_filter "fixed_version_id",
                           :type => :list_optional, :values => lambda { fixed_version_values }

      add_available_filter "fixed_version.due_date",
                           :type => :date,
                           :name => l(:label_attribute_of_fixed_version, :name => l(:field_effective_date))

      add_available_filter "fixed_version.status",
                           :type => :list,
                           :name => l(:label_attribute_of_fixed_version, :name => l(:field_status)),
                           :values => Version::VERSION_STATUSES.map{|s| [l("version_status_#{s}"), s] }

      add_available_filter "category_id",
                           :type => :list_optional,
                           :values => lambda { project.issue_categories.collect{|s| [s.name, s.id.to_s] } } if project

      add_available_filter "subject", :type => :text
      add_available_filter "description", :type => :text
      add_available_filter "created_on", :type => :date_past
      add_available_filter "updated_on", :type => :date_past
      add_available_filter "closed_on", :type => :date_past
      add_available_filter "start_date", :type => :date
      add_available_filter "due_date", :type => :date
      add_available_filter "estimated_hours", :type => :float
      add_available_filter "done_ratio", :type => :integer
      # добавлено мной в соответствии с анализом что добавлялось для версии 2.х.х
      add_available_filter "total_estimate_hours", :type => :float
      #
      if User.current.allowed_to?(:set_issues_private, nil, :global => true) ||
          User.current.allowed_to?(:set_own_issues_private, nil, :global => true)
        add_available_filter "is_private",
                             :type => :list,
                             :values => [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]]
      end

      add_available_filter "attachment",
                           :type => :text, :name => l(:label_attachment)

      if User.current.logged?
        add_available_filter "watcher_id",
                             :type => :list, :values => [["<< #{l(:label_me)} >>", "me"]]
      end

      add_available_filter("updated_by",
                           :type => :list, :values => lambda { author_values }
      )

      add_available_filter("last_updated_by",
                           :type => :list, :values => lambda { author_values }
      )

      if project && !project.leaf?
        add_available_filter "subproject_id",
                             :type => :list_subprojects,
                             :values => lambda { subproject_values }
      end

      add_custom_fields_filters(issue_custom_fields)
      # последенне поле добавлено
      add_associations_custom_fields_filters :project, :author, :assigned_to, :fixed_version, :estimate_entries

      IssueRelation::TYPES.each do |relation_type, options|
        add_available_filter relation_type, :type => :relation, :label => options[:name], :values => lambda {all_projects_values}
      end
      add_available_filter "parent_id", :type => :tree, :label => :field_parent_issue
      add_available_filter "child_id", :type => :tree, :label => :label_subtask_plural

      add_available_filter "issue_id", :type => :integer, :label => :label_issue

      Tracker.disabled_core_fields(trackers).each {|field|
        delete_available_filter field
      }
    end

    def available_columns_with_patch
    # Добавляю available_columns как в версии 3.х.х
      return @available_columns if @available_columns
      @available_columns = self.class.available_columns.dup
      @available_columns += issue_custom_fields.visible.collect {|cf| QueryCustomFieldColumn.new(cf) }

      if User.current.allowed_to?(:view_time_entries, project, :global => true)
        # insert the columns after total_estimated_hours or at the end
        index = @available_columns.find_index {|column| column.name == :total_estimated_hours}
        index = (index ? index + 1 : -1)

        subselect = "SELECT SUM(hours) FROM #{TimeEntry.table_name}" +
            " JOIN #{Project.table_name} ON #{Project.table_name}.id = #{TimeEntry.table_name}.project_id" +
            " WHERE (#{TimeEntry.visible_condition(User.current)}) AND #{TimeEntry.table_name}.issue_id = #{Issue.table_name}.id"

        @available_columns.insert index, QueryColumn.new(:spent_hours,
                                                         :sortable => "COALESCE((#{subselect}), 0)",
                                                         :default_order => 'desc',
                                                         :caption => :label_spent_time,
                                                         :totalable => true
        )
        subselect = "SELECT SUM(hours) FROM #{TimeEntry.table_name}" +
            " JOIN #{Project.table_name} ON #{Project.table_name}.id = #{TimeEntry.table_name}.project_id" +
            " JOIN #{Issue.table_name} subtasks ON subtasks.id = #{TimeEntry.table_name}.issue_id" +
            " WHERE (#{TimeEntry.visible_condition(User.current)})" +
            " AND subtasks.root_id = #{Issue.table_name}.root_id AND subtasks.lft >= #{Issue.table_name}.lft AND subtasks.rgt <= #{Issue.table_name}.rgt"

        @available_columns.insert index+1, QueryColumn.new(:total_spent_hours,
                                                           :sortable => "COALESCE((#{subselect}), 0)",
                                                           :default_order => 'desc',
                                                           :caption => :label_total_spent_time
        )
      end

      # добавлено как пододие предыдущего блока subselect с заменой на :field_total_estimate_hours
      if User.current.allowed_to?(:view_time_entries, project, :global => true)
        # insert the columns after total_estimated_hours or at the end
        index = @available_columns.find_index {|column| column.name == :total_estimated_hours}
        index = (index ? index + 1 : -1)
        subselect = "SELECT SUM(hours) FROM #{EstimateEntry.table_name}" +
            " JOIN #{Project.table_name} ON #{Project.table_name}.id = #{EstimateEntry.table_name}.project_id" +
            " WHERE (#{EstimateEntry.visible_condition(User.current)}) AND #{EstimateEntry.table_name}.issue_id = #{Issue.table_name}.id"

        @available_columns.insert index, QueryColumn.new(:total_estimate_hours,
                                                         :sortable => "COALESCE((#{subselect}), 0)",
                                                         :default_order => 'desc',
                                                         :caption => :field_total_estimate_hours,
                                                         :totalable => true
        )
        #
        #


      end

      if User.current.allowed_to?(:set_issues_private, nil, :global => true) ||
          User.current.allowed_to?(:set_own_issues_private, nil, :global => true)
        @available_columns << QueryColumn.new(:is_private, :sortable => "#{Issue.table_name}.is_private", :groupable => true)
      end

      disabled_fields = Tracker.disabled_core_fields(trackers).map {|field| field.sub(/_id$/, '')}
      @available_columns.reject! {|column|
        disabled_fields.include?(column.name.to_s)
      }

      @available_columns

    end #def available_columns_with_patch
  end
end #module IssueQueryPatch
