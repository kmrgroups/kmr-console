-- Layout app: allow the two new design concepts (departments, current layout)
alter table console.layout_projects drop constraint if exists layout_projects_concept_check;
alter table console.layout_projects add constraint layout_projects_concept_check check (concept in ('cellular-u','cellular-heavy','straight-flow','functional','as-is','office-ergonomic'));
