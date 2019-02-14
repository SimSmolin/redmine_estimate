require_dependency 'queries_helper'
module QueriesHelperPatch
  include ApplicationHelper

  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      unloadable
      alias_method_chain :column_value, :patch # modify "column_value" method by adding your_action action
    end
  end

  module InstanceMethods

    def column_value_with_patch(column, item, value)
      # if column.name == :total_estimate_hours && item.total_estimate_hours != item.total_accepted_estimate_hours
      #   link_to value, issue_path(item)
      # else
      #   column_value_without_patch(column, item, value)
      # end
      case column.name
      when :total_estimate_hours
        #link_to value, issue_path(item)
        format_hours(value)
      when :total_accepted_estimate_hours
        link_to_if(item.total_estimate_hours != item.total_accepted_estimate_hours, format_hours(value), issue_path(item))
      else
        column_value_without_patch(column, item, value)
      end
    end

  end
end