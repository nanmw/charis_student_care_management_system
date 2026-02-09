# Charis Student Care Management System - Test Guidelines

1. Note that academic session or academic year is the same thing and are different from year and student year, which are the same thing.
2. Date picker should highlight the date a change was made in the database (whether a new insertion of edit).
3. When a date is selected from the date picker, it should filter on the tests that were created or edited on that date based on the filter parameters of mode and year.
4. If no date is selected, the data displayed should only be filtered by mode and year with the most recent test score for each student.
5. Test evaluation or grading for a given student should be done only once a year for the academic session or academic year.
6. A rewrite or re-testing of any test subject per student can be allowed if the student failed the test within that academic year.
7. Any rewritten test automatically earns a maximum score of 70 points event if the score entered is above 70.
8. Subject and score are required fields before saving.
9. For any given year and mode, if one student is scored, the other students should automatically have an outstanding test.
10. Saving on the main test screen should be for new insertions only. Editing a student's score can be achieved in the student summary modal.
11. Score should be a dash (-) and passed should be a dash (-) if the student has not been scored yet per subject per filter per academic session.
