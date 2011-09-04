require 'spec_helper'

steps "clock in and out on projects", :type => :request do

  let! :client_1 do Factory(:client, :name => 'Foo, Inc.') end
  let! :project_1 do Factory(:project, :client => client_1) end
  let! :user      do Factory(:user, :current_project => project_1) end

  let! :work_units do
    [ Factory(:work_unit, :project => project_1, :user => user),
      Factory(:work_unit, :project => project_1, :user => user),
      Factory(:work_unit, :project => project_1, :user => user),
    ]
  end

  it "should login as a user" do
    visit root_path
    fill_in "Login", :with => user.login
    fill_in "Password", :with => user.password
    click_button 'Login'
    page.should have_link("Logout")
    @work_unit_count = WorkUnit.count
  end

  it "should have an unclocked timeclock" do
    within "#timeclock" do
      page.should have_content("You are not clocked in")
      page.should_not have_selector("#timeclock #task_elapsed")
    end
  end

  it "user clicks on the clock in link in the timeclock" do
    click_link "Clock in on #{project_1.name}"
  end 

  it "should show a clock-in form and a clock" do
    page.should have_selector("form[action='/clock_out']")    
    page.should have_selector("#timeclock #task_elapsed")
  end

  it "should have created an unfinished work unit in the DB" do
    WorkUnit.count.should == @work_unit_count +1 
    new_work_unit = WorkUnit.last
    new_work_unit.stop_time.should be_nil
    new_work_unit.project.should == project_1
  end

  it "should clock out with a message" do
    fill_in "Notes", :with => "Did a little work on project #1"
    within("#timeclock"){ click_button "Clock Out" }
  end


  it "should have an unclocked timeclock" do
    within "#timeclock" do
      page.should have_content("You are not clocked in")
      page.should_not have_selector("#timeclock #task_elapsed")
    end
  end

 
  it "user clicks on the clock in link in the timeclock" do
    click_link "Clock in on #{project_1.name}"
    @new_work_unit = WorkUnit.last
  end 

  it "user clocks out with hours set unreasonably high" do
    pending "Waiting for implementation of validation checking on clock-out"
    within("#timeclock") do
      fill_in "Hours", :with => '9.0'
      fill_in "Notes", :with => "I worked all day on this"  
      click_button "Clock Out"
    end
  end

  it "should show a flash error" do
    pending "Waiting for implementation of validation checking on clock-out"
    page.should have_selector(".flash.error")
  end

  it "should still show the timeclock" do
    pending "Waiting for implementation of validation checking on clock-out"
    page.should have_selector("form[action='/clock_out']")    
    page.should have_selector("#timeclock #task_elapsed")
  end

  it "should not mark the work unit completed" do
    pending "Waiting for implementation of validation checking on clock-out"
    @new_work_unit.reload.should_not be_completed
  end

  it "when the work unit was started ten hours ago ago" do
    @new_work_unit.update_attribute(:start_time, Time.now - 10.hours)
  end

  it "and I fill in nine hours and clock out" do
    fill_in "Hours", :with => '9.0'
    fill_in "Notes", :with => "I worked all day on this"  
    within("#timeclock"){ click_button "Clock Out" } 
  end 
   
  it "should have an unclocked timeclock" do
    within "#timeclock" do
      page.should have_content("You are not clocked in")
      page.should_not have_selector("#timeclock #task_elapsed")
    end
  end
   

  it "should have created an completed work unit in the DB" do
    WorkUnit.count.should == @work_unit_count + 2
    new_work_unit = WorkUnit.last
    new_work_unit.stop_time.should be_within(2.seconds).of(Time.now)
    new_work_unit.project.should == project_1
    new_work_unit.notes.should == "I worked all day on this"
    new_work_unit.hours.should == 9.0
  end

  it "should show the created work unit in 'Recent Work'" do
    within "#recent_work" do
      page.should have_content("9.00")
    end
  end



end
