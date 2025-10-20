-- {"query": "159.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2510} 
with user_posts as (
  select u.Id as user_id,
         u.DisplayName,
         u.Reputation,
         count(p.Id) filter (where p.PostTypeId = 1) as question_count,
         count(p.Id) filter (where p.PostTypeId = 2) as answer_count,
         sum(coalesce(p.Score,0)) as total_post_score,
         max(p.CreationDate) as last_post_date,
         min(p.CreationDate) as first_post_date
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
recent_activity AS (
  select p.Id as post_id,
         p.OwnerUserId,
         p.PostTypeId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         substring(coalesce(p.Tags,''), 1, 200) as tag_snippet,
         row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
  from Posts p
  where p.OwnerUserId is not null
),
top_recent_posts AS (
  select * from recent_activity where rn <= 3
),
post_answer_stats AS (
  select q.Id as question_id,
         q.OwnerUserId as question_owner,
         q.CreationDate as question_created,
         q.Score as question_score,
         q.ViewCount as question_views,
         q.AnswerCount,
         a.Id as answer_id,
         a.OwnerUserId as answer_owner,
         a.CreationDate as answer_created,
         a.Score as answer_score,
         case when a.Id = q.AcceptedAnswerId then 1 else 0 end as accepted_by_q
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
),
answer_latency AS (
  select question_id,
         min(answer_created - question_created) as min_time_to_answer,
         avg(extract(epoch from (answer_created - question_created))) as avg_seconds_to_answer,
         max(answer_score) as max_answer_score,
         sum(case when accepted_by_q = 1 then 1 else 0 end) as accepted_count,
         count(answer_id) as answers_total
  from post_answer_stats
  group by question_id
),
user_acceptance_rate AS (
  select p.OwnerUserId as user_id,
         count(distinct p.Id) filter (where p.PostTypeId = 1) as questions_asked,
         count(distinct p.AcceptedAnswerId) filter (where p.PostTypeId = 1 and p.AcceptedAnswerId is not null) as accepted_answers_count,
         case when count(distinct p.Id) filter (where p.PostTypeId = 1) > 0
              then (count(distinct p.AcceptedAnswerId) filter (where p.PostTypeId = 1 and p.AcceptedAnswerId is not null)::numeric
                    / nullif(count(distinct p.Id) filter (where p.PostTypeId = 1),0))
              else null end as acceptance_rate
  from Posts p
  group by p.OwnerUserId
),
tag_explosion as (
  -- break tags into rows; Tags are in the form '<tag1><tag2>'
  select p.Id as post_id,
         p.OwnerUserId,
         normalize_tag.tag as tag
  from Posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,''), 2, greatest(length(coalesce(p.Tags,'')) - 2,0)), '><')) as tag
  ) as normalize_tag
  where p.PostTypeId = 1 and coalesce(p.Tags,'') <> ''
),
tag_agg as (
  select t.tag,
         count(distinct post_id) as questions_with_tag,
         count(distinct case when p.PostTypeId = 2 then p.ParentId end) as answers_linked_count -- dummy to include more joins
  from tag_explosion t
  left join Posts p on p.Id = t.post_id
  group by t.tag
),
badges_per_user as (
  select b.UserId as user_id,
         count(*) as badges_total,
         count(*) filter (where b.Class = 1) as gold_badges,
         count(*) filter (where b.Class = 2) as silver_badges,
         count(*) filter (where b.Class = 3) as bronze_badges,
         max(b.Date) as last_badge_date
  from Badges b
  group by b.UserId
),
vote_balance as (
  select v.UserId as voter_id,
         sum(case when vt.Name ilike '%Up%' or v.VoteTypeId = 2 then 1 else 0 end) as up_votes_cast,
         sum(case when vt.Name ilike '%Down%' or v.VoteTypeId = 3 then 1 else 0 end) as down_votes_cast,
         sum(coalesce(v.BountyAmount,0)) as bounty_given
  from Votes v
  left join VoteTypes vt on vt.Id = v.VoteTypeId
  group by v.UserId
),
post_link_network as (
  select pl.PostId,
         pl.RelatedPostId,
         lt.Name as link_type,
         count(*) over (partition by pl.PostId) as outgoing_links_from_post,
         count(*) over (partition by pl.RelatedPostId) as incoming_links_to_related
  from PostLinks pl
  left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
duplicate_clusters as (
  select p.Id as question_id,
         array_agg(distinct related.RelatedPostId) filter (where related.link_type ilike '%duplicate%') as duplicates_out,
         cardinality(array_agg(distinct related.RelatedPostId) filter (where related.link_type ilike '%duplicate%')) as duplicate_count
  from Posts p
  left join post_link_network related on related.PostId = p.Id
  where p.PostTypeId = 1
  group by p.Id
),
user_rankings as (
  select up.user_id,
         up.DisplayName,
         up.Reputation,
         up.question_count,
         up.answer_count,
         up.total_post_score,
         b.badges_total,
         v.up_votes_cast,
         v.down_votes_cast,
         ua.acceptance_rate,
         row_number() over (order by up.Reputation desc nulls last, up.total_post_score desc) as reputation_rank,
         dense_rank() over (order by up.question_count desc nulls last) as question_rank,
         coalesce(ua.acceptance_rate,0) as acceptance_rate_coalesced
  from user_posts up
  left join badges_per_user b on b.user_id = up.user_id
  left join vote_balance v on v.voter_id = up.user_id
  left join user_acceptance_rate ua on ua.user_id = up.user_id
),
top_active_users as (
  select ur.*,
         (coalesce(ur.badges_total,0) * 0.5 + coalesce(ur.total_post_score,0) * 0.2 + coalesce(ur.question_count,0) * 1.5 + coalesce(ur.answer_count,0) * 1.2) as activity_score
  from user_rankings ur
),
combined_questions as (
  -- union recent hot questions (by view or score) with those having many duplicates
  select q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, 'HOT_BY_VIEWS' as reason
  from Posts q
  where q.PostTypeId = 1 and q.ViewCount > 10000
  union
  select q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, 'HOT_BY_SCORE' as reason
  from Posts q
  where q.PostTypeId = 1 and q.Score > 500
  union
  select q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, 'MANY_DUPLICATES' as reason
  from Posts q
  left join duplicate_clusters dc on dc.question_id = q.Id
  where q.PostTypeId = 1 and coalesce(dc.duplicate_count,0) >= 5
),
final_user_insights as (
  select ta.user_id,
         ta.DisplayName,
         ta.Reputation,
         ta.question_count,
         ta.answer_count,
         ta.total_post_score,
         ta.badges_total,
         ta.up_votes_cast,
         ta.down_votes_cast,
         ta.acceptance_rate_coalesced,
         ta.reputation_rank,
         ta.question_rank,
         ta.activity_score,
         -- correlated subquery: last 3 post titles concatenated
         (select string_agg(coalesce(t.Title,'[no title]') || ' (' || coalesce(t.tag_snippet,'') || ')', ' ||| ' order by t.CreationDate desc)
          from top_recent_posts t
          where t.OwnerUserId = ta.user_id) as recent_titles_snippet,
         -- percentage of user's posts that are questions
         case when (ta.question_count + ta.answer_count) > 0
              then round(100.0 * ta.question_count / (ta.question_count + ta.answer_count),2)
              else null end as pct_questions,
         -- find top tag they used (correlated)
         (select te.tag from tag_explosion te where te.OwnerUserId = ta.user_id group by te.tag order by count(*) desc limit 1) as top_tag,
         -- existence checks
         exists(select 1 from Votes v where v.UserId = ta.user_id and v.VoteTypeId = 2) as has_cast_upvotes,
         exists(select 1 from Badges b where b.UserId = ta.user_id and b.Class = 1) as has_gold_badge
  from top_active_users ta
  order by ta.activity_score desc
  limit 50
)

select f.*,
       coalesce(cq.top_reason_list, '{}') as matched_hot_reasons,
       coalesce(tg.tag_list, '{}') as top_tags_among_hot_questions
from final_user_insights f
left join lateral (
  -- collect combined questions where the user is owner or answered one of them recently (correlated, with null logic)
  select array_agg(distinct cq.Id) as question_ids,
         array_agg(distinct cq.reason) as top_reason_list
  from combined_questions cq
  where cq.OwnerUserId = f.user_id
) cq on true
left join lateral (
  -- for each user's top tag, find related hot questions' tags (set operator example using union)
  select array_agg(distinct t.tag) as tag_list from (
    select te.tag from tag_explosion te where te.OwnerUserId = f.user_id
    union
    select te2.tag from combined_questions cq2
    join tag_explosion te2 on te2.post_id = cq2.Id
    where cq2.OwnerUserId = f.user_id
  ) t
) tg on true
order by f.activity_score desc, f.reputation_rank asc;