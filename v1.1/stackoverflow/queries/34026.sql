with user_badges as (
    select UserId, 
           count(*) filter (where Class = 1) as gold_badges,
           count(*) filter (where Class = 2) as silver_badges,
           count(*) filter (where Class = 3) as bronze_badges
    from Badges
    group by UserId
),
question_stats as (
    select p.OwnerUserId,
           count(p.Id) as total_questions,
           avg(p.Score) as avg_question_score,
           sum(p.ViewCount) as total_views,
           count(case when p.AcceptedAnswerId is not null then 1 end) as questions_with_accepted_answer,
           avg(p.AnswerCount) as avg_answer_count,
           max(p.CreationDate) as last_question_date
    from Posts p
    where p.PostTypeId = 1
    group by p.OwnerUserId
),
answer_stats as (
    select p.OwnerUserId,
           count(p.Id) as total_answers,
           avg(p.Score) as avg_answer_score,
           max(p.CreationDate) as last_answer_date
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
),
vote_stats as (
    select v.UserId,
           count(*) as total_votes_cast,
           count(case when v.VoteTypeId = 2 then 1 end) as upvotes_cast,
           count(case when v.VoteTypeId = 3 then 1 end) as downvotes_cast,
           sum(v.BountyAmount) as total_bounty_given
    from Votes v
    where v.UserId is not null
    group by v.UserId
),
recent_activity as (
    select ph.UserId,
           max(ph.CreationDate) as last_edit_date,
           count(distinct case when ph.PostHistoryTypeId in (1,2,3,4,5,6) then ph.PostId end) as posts_edited,
           count(distinct ph.PostId) as total_posts_affected
    from PostHistory ph
    group by ph.UserId
),
top_tags as (
    -- split tag string like '<tag1><tag2>' into rows in a dialect-agnostic way using regexp
    select trim(tag) as tag,
           p.OwnerUserId,
           count(*) as questions_in_tag
    from Posts p
    cross join lateral (
      select regexp_split_to_table(
               case when p.Tags is not null and length(p.Tags) >= 2 then substring(p.Tags from 2 for char_length(p.Tags) - 2) else '' end,
               '><'
             ) as tag
    ) s
    where p.PostTypeId = 1 and p.Tags is not null and p.Tags <> ''
    group by trim(tag), p.OwnerUserId
),
top_user_tags AS (
    select tt.OwnerUserId,
           array_agg(tt.tag order by tt.questions_in_tag desc) as tag_list,
           array_agg(tt.tag order by tt.questions_in_tag desc) FILTER (WHERE true) as tag_list_all
    from top_tags tt
    group by tt.OwnerUserId
),
top_user_top3 AS (
    select t.OwnerUserId,
           array_agg(t.tag) as top_tags
    from (
        select tt.OwnerUserId,
               tt.tag,
               row_number() over (partition by tt.OwnerUserId order by tt.questions_in_tag desc) as rn
        from top_tags tt
    ) t
    where t.rn <= 3
    group by t.OwnerUserId
)
select u.Id as user_id,
       u.DisplayName,
       u.Reputation,
       u.CreationDate,
       coalesce(ub.gold_badges, 0) as gold_badges,
       coalesce(ub.silver_badges, 0) as silver_badges,
       coalesce(ub.bronze_badges, 0) as bronze_badges,
       coalesce(qs.total_questions, 0) as total_questions,
       coalesce(qs.avg_question_score, 0) as avg_question_score,
       coalesce(qs.total_views, 0) as total_question_views,
       coalesce(qs.questions_with_accepted_answer, 0) as questions_with_accepted_answer,
       coalesce(qs.avg_answer_count, 0) as avg_answer_count,
       coalesce(as_.total_answers, 0) as total_answers,
       coalesce(as_.avg_answer_score, 0) as avg_answer_score,
       coalesce(vs.total_votes_cast, 0) as total_votes_cast,
       coalesce(vs.upvotes_cast, 0) as upvotes_cast,
       coalesce(vs.downvotes_cast, 0) as downvotes_cast,
       coalesce(vs.total_bounty_given, 0) as total_bounty_given,
       ra.last_edit_date,
       coalesce(ra.posts_edited, 0) as posts_edited,
       coalesce(ra.total_posts_affected, 0) as total_posts_affected,
       tut.top_tags
from Users u
left join user_badges ub on ub.UserId = u.Id
left join question_stats qs on qs.OwnerUserId = u.Id
left join answer_stats as_ on as_.OwnerUserId = u.Id
left join vote_stats vs on vs.UserId = u.Id
left join recent_activity ra on ra.UserId = u.Id
left join top_user_top3 tut on tut.OwnerUserId = u.Id
where u.Reputation > 10000
group by
  u.Id,
  u.DisplayName,
  u.Reputation,
  u.CreationDate,
  ub.gold_badges,
  ub.silver_badges,
  ub.bronze_badges,
  qs.total_questions,
  qs.avg_question_score,
  qs.total_views,
  qs.questions_with_accepted_answer,
  qs.avg_answer_count,
  as_.total_answers,
  as_.avg_answer_score,
  vs.total_votes_cast,
  vs.upvotes_cast,
  vs.downvotes_cast,
  vs.total_bounty_given,
  ra.last_edit_date,
  ra.posts_edited,
  ra.total_posts_affected,
  tut.top_tags
order by u.Reputation desc
limit 100;