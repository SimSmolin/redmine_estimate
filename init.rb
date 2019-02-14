require 'redmine'
require_relative 'lib/issues_controller_patch'
require_relative 'lib/issue_model_patch'
require_relative 'lib/issue_query_patch'
require_relative 'lib/queries_helper_patch'

ActionDispatch::Callbacks.to_prepare do
  IssuesController.send :include, IssuesControllerPatch
end

ActionDispatch::Callbacks.to_prepare do
  Issue.send :include, IssueModelPatch
end

ActionDispatch::Callbacks.to_prepare do
  IssueQuery.send :include, IssueQueryPatch
end

ActionDispatch::Callbacks.to_prepare do
  QueriesHelper.send :include, QueriesHelperPatch
end

Redmine::Plugin.register :redmine_estimates do
  name 'Estimates plugin'
  author 'Sergey Melnikov based on the Nick Mikhno code'
  description 'This is Redmine 3.x.x plugin for multiple estimate entries for a single task'
  version '1.0'
  url 'http://krit.pro'
  author_url 'https://www.linkedin.com/in/sergey-melnikov-07936b162/'

  permission :view_estimates, {:estimates => [:new, :create, :index, :report]}, :public => true
  permission :edit_estimates, {:estimates => [:edit, :update, :destroy, :accept]}
  permission :accept_estimates, {:estimates => :accept}
end
