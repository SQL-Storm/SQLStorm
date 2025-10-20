with badge_counts as (
  select
    u.Id,
    u.DisplayName,
    SUM(case when b.Class = 1 then 1 else 0 end) as gold_badges,
    SUM(case when b.Class = 2 then 1 else 0 end) as silver_badges,
    SUM(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
    COUNT(b.Id) as total_badges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
user_post_stats as (
  select
    u.Id,
    COUNT(p.Id) as total_posts,
    COUNT(case when p.PostTypeId = 1 then 1 else null end) as total_questions,
    COUNT(case when p.PostTypeId = 2 then 1 else null end) as total_answers,
    MAX(p.Score) as max_score
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id
)
select
  u.Id,
  u.DisplayName,
  bc.gold_badges,
  bc.silver_badges,
  bc.bronze_badges,
  bc.total_badges,
  ups.total_posts,
  ups.total_questions,
  ups.total_answers,
  ups.max_score
from Users u
left join badge_counts bc on bc.Id = u.Id
left join user_post_stats ups on ups.Id = u.Id
group by
  u.Id,
  u.DisplayName,
  bc.gold_badges,
  bc.silver_badges,
  bc.bronze_badges,
  bc.total_badges,
  ups.total_posts,
  ups.total_questions,
  ups.total_answers,
  ups.max_score;