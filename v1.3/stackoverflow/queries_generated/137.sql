-- {"query": "137.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2256} 
with
-- explode tags into rows (questions only)
tag_explode as (
  select p.id as post_id, trim(t) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,'')) - 2,0)), '><')) as t
  ) x
  where p.posttypeid = 1 and coalesce(p.tags,'') <> ''
),
-- recent activity window: last 365 days relative to max date in posts
max_dates as (
  select max(creationdate) as max_created from posts
),
recent_questions as (
  select p.*
  from posts p
  join max_dates md on 1=1
  where p.posttypeid = 1
    and p.creationdate >= md.max_created - interval '365 days'
),
-- answer aggregates per question (including correlated to compute acceptance rate)
answer_agg as (
  select q.id as question_id,
         count(a.id) filter (where a.posttypeid=2) as answers_count,
         sum(a.score) filter (where a.posttypeid=2) as answers_score_sum,
         avg(a.score) filter (where a.posttypeid=2) as answers_score_avg,
         max(a.score) filter (where a.posttypeid=2) as answers_max_score,
         sum(case when q.acceptedanswerid = a.id then 1 else 0 end) as accepted_present,
         sum(case when a.creationdate <= q.creationdate + interval '1 day' then 1 else 0 end) as answers_within_1d
  from posts q
  left join posts a on a.parentid = q.id
  where q.posttypeid = 1
  group by q.id
),
-- heavy user stats: combine posts, votes, badges, comments; include NULL logic and correlated subqueries
user_activity as (
  select u.id,
         u.displayname,
         u.reputation,
         coalesce(u.views,0) as views,
         coalesce(u.upvotes,0) as upvotes,
         coalesce(u.downvotes,0) as downvotes,
         -- counts with outer joins and coalescing
         coalesce(pq.qcount,0) as question_count,
         coalesce(pa.acount,0) as answer_count,
         coalesce(b.badges_count,0) as badge_count,
         coalesce(c.comments_count,0) as comments_count,
         -- last activity derived from posts/comments/votes
         greatest(
           coalesce((select max(creationdate) from posts p where p.owneruserid = u.id), '1970-01-01'::timestamp),
           coalesce((select max(creationdate) from comments c2 where c2.userid = u.id), '1970-01-01'::timestamp),
           coalesce((select max(creationdate) from votes v2 where v2.userid = u.id), '1970-01-01'::timestamp)
         ) as last_activity,
         -- correlated subquery for percent of user's answers accepted (null-safe)
         coalesce((
           select 100.0 * sum(case when a.id = p.acceptedanswerid then 1 else 0 end)::numeric / nullif(count(a.id),0)
           from posts p
           join posts a on a.parentid = p.id
           where a.posttypeid = 2 and a.owneruserid = u.id
         ), 0.0) as pct_answers_accepted
  from users u
  left join (
    select owneruserid, count(*) as qcount
    from posts where posttypeid = 1 group by owneruserid
  ) pq on pq.owneruserid = u.id
  left join (
    select owneruserid, count(*) as acount
    from posts where posttypeid = 2 group by owneruserid
  ) pa on pa.owneruserid = u.id
  left join (
    select userid, count(*) as badges_count
    from badges group by userid
  ) b on b.userid = u.id
  left join (
    select userid, count(*) as comments_count
    from comments group by userid
  ) c on c.userid = u.id
),
-- tag popularity with window functions and string expressions
tag_stats as (
  select te.tag,
         count(distinct te.post_id) as questions_in_tag,
         sum(coalesce(p.viewcount,0)) as total_views,
         avg(coalesce(qa.answers_count,0)) as avg_answers_per_question,
         sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count,
         -- string expression: synthetic slug
         lower(replace(te.tag,' ','-')) || '-' || substr(md5(te.tag::text),1,6) as tag_slug,
         row_number() over (order by count(distinct te.post_id) desc, sum(coalesce(p.viewcount,0)) desc) as popularity_rank
  from tag_explode te
  join posts p on p.id = te.post_id
  left join answer_agg qa on qa.question_id = te.post_id
  left join posts q on q.id = te.post_id
  group by te.tag
),
-- identify potentially problematic or suspicious posts using complicated predicates
suspicious_posts as (
  select p.id, p.title, p.owneruserid, p.score, p.viewcount, p.creationdate,
         case
           when p.score < 0 then 'negative_score'
           when p.viewcount = 0 and p.score > 50 then 'high_score_no_views'
           when p.commentcount > greatest(5, round(p.viewcount::numeric/100.0)) then 'many_comments'
           when p.lastactivitydate is null then 'no_activity'
           else 'normal'
         end as status,
         -- correlated: number of distinct users who commented on this post
         (select count(distinct userId) from comments c where c.postid = p.id) as distinct_commenters,
         -- JSON-like composite via concatenation and null handling
         concat('score=', coalesce(p.score::text,'NULL'), ';views=', coalesce(p.viewcount::text,'NULL'), ';title_len=', coalesce(length(coalesce(p.title,''))::text,'0')) as metrics_blob
  from posts p
  where p.creationdate >= (select max_created from max_dates) - interval '730 days'
),
-- top contributors per tag using window functions and a correlated measure of influence
top_contributors as (
  select ts.tag,
         ua.id as user_id,
         ua.displayname,
         count(distinct p.id) filter (where p.posttypeid=1 and p.owneruserid = ua.id) as q_post_count,
         count(distinct p.id) filter (where p.posttypeid=2 and p.owneruserid = ua.id) as a_post_count,
         sum(coalesce(vt_up.upvotes,0)) as upvotes_received,
         dense_rank() over (partition by ts.tag order by sum(coalesce(vt_up.upvotes,0)) desc nulls last) as contributor_rank
  from tag_stats ts
  join tag_explode te on te.tag = ts.tag
  join posts p on p.id = te.post_id
  join users ua on ua.id = p.owneruserid
  left join lateral (
    select sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes
    from votes v
    where v.postid = p.id
  ) vt_up on true
  group by ts.tag, ua.id, ua.displayname
),
-- merge results via UNION ALL and ensure EXCEPT to remove trivial noise
benchmark_union as (
  select 'tag_overview' as record_type, tag::text as key, to_jsonb(ts.*) - 'tag' as payload
  from tag_stats ts
  where ts.questions_in_tag > 5
  union all
  select 'user_activity' as record_type, id::text, to_jsonb(ua.*) - 'id' as payload
  from user_activity ua
  where ua.reputation > 100
  union all
  select 'suspicious' as record_type, id::text, to_jsonb(sp.*) - 'id' as payload
  from suspicious_posts sp
)
select bu.record_type,
       bu.key,
       bu.payload,
       -- additional computed columns to stress-query planner with nested expressions
       case
         when bu.record_type = 'tag_overview' then (bu.payload ->> 'popularity_rank')::int
         when bu.record_type = 'user_activity' then (bu.payload ->> 'last_activity')::text
         else null
       end as extra_info,
       -- tie-breaker using set operator: include a synthetic row only if not present in existing keys
       exists (
         select 1 from tag_stats ts where ts.tag = bu.key
       ) as is_known_tag
from benchmark_union bu
-- exclude any payloads with JSON fields that suggest triviality using EXCEPT
except
select 'tag_overview' as record_type, tag::text as key, to_jsonb(ts.*) - 'tag' as payload,
       null as extra_info, true as is_known_tag
from tag_stats ts
where ts.questions_in_tag <= 100 and ts.popularity_rank > 50
order by record_type nulls last, key
limit 100;