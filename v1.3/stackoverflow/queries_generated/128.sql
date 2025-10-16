-- {"query": "128.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2520} 
with
-- recent posts in last 2 years with some derived flags
recent_posts as (
  select p.*,
    (p.Score is null) as score_is_null,
    coalesce(p.Score,0) as score0,
    case when p.PostTypeId = 1 then 'question'
         when p.PostTypeId = 2 then 'answer'
         else 'other' end as post_kind,
    -- boolean if rich content length > threshold
    (char_length(coalesce(p.Body,'')) > 2000) as long_body
  from Posts p
  where p.CreationDate >= now() - interval '2 years'
),
-- explode tags for questions
exploded_tags as (
  select rp.Id as PostId,
         lower(trim(t)) as tag
  from recent_posts rp
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(rp.Tags,''), 2, greatest(length(coalesce(rp.Tags,''))-2,0)), '><')) as t
  ) s
  where rp.PostTypeId = 1
    and coalesce(rp.Tags,'') <> ''
    and s.t <> ''
),
-- aggregate stats per tag
tag_stats as (
  select tag,
         count(distinct PostId) as question_count,
         count(*) filter (where exists (select 1 from Posts a where a.ParentId = exploded_tags.PostId and a.PostTypeId = 2)) as answers_linked_count,
         avg(coalesce(p.Score,0)) as avg_q_score,
         max(coalesce(p.ViewCount,0)) as max_views,
         min(p.CreationDate) as first_seen
  from exploded_tags
  join Posts p on p.Id = exploded_tags.PostId
  group by tag
),
-- user-level aggregates: posts, answers, accepted answers, avg score, last activity via correlated subquery
user_activity as (
  select u.Id as UserId,
         u.DisplayName,
         count(p.Id) filter (where p.PostTypeId in (1,2)) as total_posts,
         count(p.Id) filter (where p.PostTypeId = 2) as answers,
         count(p.Id) filter (where p.PostTypeId = 1) as questions,
         sum(case when p.Id = u_rep.AcceptedFrom then 1 else 0 end) as accepted_answers_count,
         avg(coalesce(p.Score,0)) filter (where p.PostTypeId in (1,2)) as avg_post_score,
         coalesce(u.Reputation,0) as reputation,
         -- correlated subquery to get last non-null activity date across posts/comments/votes
         (select greatest(
            coalesce(max(p2.LastActivityDate), '1970-01-01'::timestamp),
            coalesce((select max(CreationDate) from Comments c where c.UserId = u.Id), '1970-01-01'::timestamp),
            coalesce((select max(CreationDate) from Votes v where v.UserId = u.Id), '1970-01-01'::timestamp)
          )) as last_activity
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  -- small lateral subquery to compute first accepted answer authored by user (if any) to correlate
  left join lateral (
    select min(a.Id) as AcceptedFrom
    from Posts a
    where a.OwnerUserId = u.Id
      and exists (select 1 from Posts q where q.AcceptedAnswerId = a.Id)
  ) u_rep on true
  group by u.Id, u.DisplayName, u.Reputation, u_rep.AcceptedFrom
),
-- compute per-user windowed ranks by multiple criteria
user_ranks as (
  select ua.*,
    row_number() over (order by ua.total_posts desc, ua.reputation desc, coalesce(ua.avg_post_score,0) desc) as overall_rank,
    dense_rank() over (order by ua.reputation desc) as reputation_rank,
    rank() over (order by coalesce(ua.last_activity,'1970-01-01'::timestamp) desc) as recent_activity_rank
  from user_activity ua
),
-- badge counts per user, with string expressions and NULL logic
badge_agg as (
  select b.UserId,
         count(*) as badge_count,
         sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
         string_agg(distinct substring(b.Name from 1 for 20) || case when b.TagBased = 1 then ' (tag)' else '' end, ', ' order by b.Date desc) as recent_badges_sample
  from Badges b
  group by b.UserId
),
-- votes summary per post including correlated subquery and null-handling
post_votes as (
  select p.Id as PostId,
         p.OwnerUserId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as upvotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as downvotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as favorites,
         count(distinct v.Id) as total_votes,
         -- correlated subquery: last vote info
         (select v2.VoteTypeId from Votes v2 where v2.PostId = p.Id order by v2.CreationDate desc limit 1) as last_vote_type
  from Posts p
  left join Votes v on v.PostId = p.Id
  group by p.Id, p.OwnerUserId
),
-- compile a set of "interesting posts" using complicated predicates and outer joins
interesting_posts as (
  select p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate,
         coalesce(p.OwnerUserId, -1) as owner_id,
         pv.upvotes, pv.downvotes, pv.total_votes,
         ph.Comment as last_history_comment,
         coalesce(p.Title, '') || ' [' || coalesce(left(p.Tags,40), '') || ']' as short_display,
         case when p.PostTypeId = 1 and p.AcceptedAnswerId is not null then 1 else 0 end as has_accepted,
         -- find last comment text via correlated subquery
         (select c.Text from Comments c where c.PostId = p.Id order by c.CreationDate desc limit 1) as last_comment_text
  from Posts p
  left join post_votes pv on pv.PostId = p.Id
  left join lateral (
    select ph.Comment
    from PostHistory ph
    where ph.PostId = p.Id
      and ph.PostHistoryTypeId in (24,25,33,34,50)
    order by ph.CreationDate desc
    limit 1
  ) ph on true
  where p.CreationDate >= now() - interval '6 months'
    and (coalesce(p.Score,0) >= 3 or coalesce(p.ViewCount,0) >= 500)
),
-- derive per-tag trending score combining tag_stats and recent activity
tag_trending as (
  select ts.*,
         (ts.question_count * 2.0 + coalesce(ts.avg_q_score,0) * 1.5 + log(1 + greatest(ts.max_views,0)) ) as trending_score,
         row_number() over (order by (ts.question_count * 2.0 + coalesce(ts.avg_q_score,0) * 1.5 + log(1 + greatest(ts.max_views,0))) desc) as tag_rank
  from tag_stats ts
),
-- union of top tag authors via set operator to force optimizer work: users who asked or answered top tags
top_tag_users as (
  select distinct ua.UserId from user_ranks ua
  join Posts p on p.OwnerUserId = ua.UserId
  join exploded_tags et on et.PostId = p.Id
  join tag_trending tt on tt.tag = et.tag
  where tt.tag_rank <= 50
  union
  select distinct a.OwnerUserId from Posts a
  where a.PostTypeId = 2
    and exists (select 1 from tag_trending tt2 where tt2.tag_rank <= 20 and exists (select 1 from exploded_tags et2 where et2.PostId = a.ParentId and et2.tag = tt2.tag))
),
-- final selection combining many pieces and performing windowing and complex expressions
final as (
  select ur.UserId,
         coalesce(ur.DisplayName, 'anonymous') as DisplayName,
         coalesce(ba.badge_count,0) as badge_count,
         coalesce(ur.total_posts,0) as total_posts,
         coalesce(ur.answers,0) as answers,
         coalesce(ur.questions,0) as questions,
         coalesce(ur.accepted_answers_count,0) as accepted_answers_count,
         coalesce(ur.avg_post_score,0) as avg_post_score,
         ur.reputation,
         coalesce(ur.last_activity, '1970-01-01'::timestamp) as last_activity,
         -- fancy score combining many factors with null logic and GREATEST/LEAST
         (least(1000.0, greatest(0.0,
           (coalesce(ur.total_posts,0) * 1.2) +
           (coalesce(ur.accepted_answers_count,0) * 5.5) +
           (coalesce(ba.gold_badges,0) * 10) +
           log(1 + greatest(coalesce(ur.reputation,0),0)) * 2 -
           coalesce(ur.recent_activity_rank,1000) * 0.01
         ))) as composite_score,
         exists (select 1 from top_tag_users ttu where ttu.UserId = ur.UserId) as in_top_tag_contributors,
         -- sample recent post titles as CSV using string_agg with truncation
         (select string_agg(substr(coalesce(ip.Title,''),1,80), ' || ' order by ip.CreationDate desc)
          from interesting_posts ip where ip.owner_id = ur.UserId limit 5) as recent_interesting_titles,
         -- last non-null comment across user's posts
         (select c.Text from Comments c where c.UserId = ur.UserId order by c.CreationDate desc limit 1) as last_comment_by_user
  from user_ranks ur
  left join badge_agg ba on ba.UserId = ur.UserId
)
select *
from final
where (composite_score > 5 or badge_count >= 3 or in_top_tag_contributors = true)
order by composite_score desc, reputation desc, last_activity desc
limit 100;