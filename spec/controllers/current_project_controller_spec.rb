require 'spec_helper'

describe CurrentProjectController do
  before(:each) do          
    @user = authenticate(:user)
    @project1 = Factory(:task)
    @project2 = Factory(:task)
  end
  
  it "should allow a user with no current project to set one" do
    @user.update_attribute(:current_project, nil)
    lambda do
      post :create, :id => @project1.id
    end.should change{ @user.reload.current_project }.from(nil).to(@project1)
  end        
  
  it "should allow a user with a current project to switch" do
    @user.update_attribute(:current_project, @project1)
    lambda do
      post :create, :id => @project2.id
    end.should change{ @user.reload.current_project }.from(@project1).to(@project2)
  end
  
  it "should redirect back" do
    post :create, :id => @project2.id
    response.should redirect_back    
  end
  
  describe "for javascript requests" do  
    render_views
    before(:each) { request.accept = "application/javascript" }

    it "should respond by replacing the contents of #project_picker" do
      post :create, :id => @project1.id
      response.content_type.should == "text/javascript"
    end
  end
  
end
