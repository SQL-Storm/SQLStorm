-- {"query": "7013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2677} 
with
-- top active users by composite score with temporal weighting
user_activity as (
  select
    u.id,
    u.displayname,
    u.reputation,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions_asked,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
    count(distinct c.id) as comments_made,
    count(distinct v.id) filter (where v.votetypeid = 2) as upvotes_received,
    count(distinct b.id) as badges_earned,
    -- recentness factor: newer users get a slight penalty; compute days since creation
    greatest(1, date_part('day', now() - u.creationdate)) as days_alive,
    -- composite score (arbitrary formula combining metrics, with NULL-safe math)
    (
      coalesce(u.reputation,0) * 0.2
      + coalesce(count(distinct p.id) filter (where p.posttypeid = 2),0) * 3.5
      + coalesce(count(distinct p.id) filter (where p.posttypeid = 1),0) * 1.5
      + coalesce(count(distinct c.id),0) * 0.5
      + coalesce(count(distinct v.id) filter (where v.votetypeid = 2),0) * 2.0
      + coalesce(count(distinct b.id),0) * 4.0
    )::float / greatest(1, date_part('day', now() - u.creationdate)) as composite_per_day
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  left join votes v on v.userid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate
),
-- pick top 200 users for deeper analysis
top_users as (
  select *
  from user_activity
  order by composite_per_day desc nulls last
  limit 200
),
-- recent popular questions (complex tag parsing + regex + null logic)
recent_questions as (
  select
    p.*,
    -- parse tags into an array (tags stored like '<tag1><tag2>')
    case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array,
    -- normalized title (strip HTML entities, lowercase) using nested replace and coalesce
    lower(regexp_replace(coalesce(p.title,''), '&[^;]+;', '', 'g')) as norm_title
  from posts p
  where p.posttypeid = 1
    and p.creationdate > now() - interval '730 day' -- last two years
),
-- compute per-question aggregates including answers, accepted ratio, comment depth
question_stats as (
  select
    q.id as question_id,
    q.title,
    q.owneruserid,
    q.creationdate,
    q.score,
    q.viewcount,
    q.tag_array,
    q.norm_title,
    count(a.id) filter (where a.posttypeid = 2) as answers_count,
    sum(case when a.score is null then 0 else a.score end) as answers_score_sum,
    max(a.score) as best_answer_score,
    bool_or(a.id = q.acceptedanswerid) as has_accepted,
    coalesce(q.answercount, count(a.id) filter (where a.posttypeid = 2)) as recorded_answercount,
    coalesce(avg(c.score)::numeric,0) as avg_comment_score,
    -- median-like window: rank answers by score per question
    (
      select count(*) from posts a2 where a2.parentid = q.id and a2.posttypeid = 2 and a2.score >= 0
    ) as nonneg_answer_count
  from recent_questions q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  left join comments c on c.postid = q.id
  group by q.id, q.title, q.owneruserid, q.creationdate, q.score, q.viewcount, q.tag_array, q.norm_title, q.answercount, q.acceptedanswerid
),
-- find interesting cross-links: duplicates and linked posts within last year
post_links_expanded as (
  select pl.*,
    p1.posttypeid as post_posttype,
    p2.posttypeid as related_posttype,
    p1.title as post_title,
    p2.title as related_title
  from postlinks pl
  left join posts p1 on p1.id = pl.postid
  left join posts p2 on p2.id = pl.relatedpostid
  where pl.creationdate > now() - interval '365 day'
),
-- compute tag co-occurrence among recent popular questions (explode tag arrays)
tag_pairs as (
  select
    q.question_id,
    trim(t1) as tag1,
    trim(t2) as tag2
  from question_stats q
  cross join lateral (
    select unnest(q.tag_array) as t
  ) ta1(t1)
  cross join lateral (
    select unnest(q.tag_array) as t
  ) ta2(t2)
  where ta1.t <> ta2.t
),
tag_cooccurrence as (
  select tag1, tag2, count(distinct question_id) as cooc_count
  from tag_pairs
  group by tag1, tag2
  having count(distinct question_id) >= 3
),
-- compute for each top user: their answered questions stats and tie to tag expertise
user_answer_behavior as (
  select
    tu.id as userid,
    tu.displayname,
    count(a.id) as answers_by_user,
    sum(case when q.id is not null then 1 else 0 end) filter (where a.creationdate > now() - interval '365 day') as recent_answers,
    avg(a.score) as avg_answer_score,
    sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as accepted_count,
    max(a.score) as max_answer_score,
    -- top tags by this user's answers (correlated subquery aggregated to array)
    (
      select array_agg(tag order by cnt desc, tag limit 5)
      from (
        select t, count(*) as cnt
        from (
          select unnest(coalesce(q.tags::text[] , string_to_array(substring(q.tags from 2 for char_length(q.tags)-2),'><'))) as t
          from posts p2
          join posts a2 on a2.parentid = p2.id and a2.owneruserid = tu.id and a2.posttypeid = 2
          join posts q on q.id = p2.id
          where a2.owneruserid = tu.id
        ) s
        group by t
      ) tt(tag,cnt)
    ) as top_answer_tags
  from top_users tu
  left join posts a on a.owneruserid = tu.id and a.posttypeid = 2
  left join posts q on q.id = a.parentid
  group by tu.id, tu.displayname
),
-- windowed ranking for questions by a composite hotness metric (views, score, recency, answers)
hot_questions as (
  select
    qs.*,
    (
      coalesce(qs.viewcount,0) * 0.002
      + coalesce(qs.score,0) * 1.5
      + coalesce(qs.answers_count,0) * 2.0
      + case when qs.has_accepted then 5 else 0 end
      + (case when qs.creationdate > now() - interval '30 day' then 10 else 0 end)
    ) as hotness_score,
    row_number() over (order by
      (
        coalesce(qs.viewcount,0) * 0.002
        + coalesce(qs.score,0) * 1.5
        + coalesce(qs.answers_count,0) * 2.0
        + case when qs.has_accepted then 5 else 0 end
        + (case when qs.creationdate > now() - interval '30 day' then 10 else 0 end)
      ) desc
    ) as hot_rank
  from question_stats qs
),
-- frequent commenters cluster
commenter_clusters as (
  select
    c.userid,
    u.displayname,
    count(*) as comments_total,
    avg(c.score) as avg_comment_score,
    min(c.creationdate) as first_comment,
    max(c.creationdate) as last_comment,
    -- favorite-post overlap: how many commented posts are among top hot questions
    sum(case when c.postid in (select question_id from hot_questions where hot_rank <= 500) then 1 else 0 end) as comments_on_hot
  from comments c
  left join users u on u.id = c.userid
  group by c.userid, u.displayname
  having count(*) >= 20
)
-- final selection: combine top users, their top answer behavior, their overlap with tag co-occurrence, pick some hot questions and link metrics
select
  tu.id as user_id,
  tu.displayname as user_name,
  tu.composite_per_day,
  ua.answers_by_user,
  ua.recent_answers,
  ua.accepted_count,
  ua.avg_answer_score,
  ua.top_answer_tags,
  -- calculate user's influence on hot questions (answers to hot questions)
  coalesce((
    select count(*) from posts a
    join hot_questions hq on hq.question_id = a.parentid
    where a.owneruserid = tu.id and a.posttypeid = 2 and hq.hot_rank <= 100
  ),0) as answers_to_top100_hot,
  -- compute how often this user's answers were accepted for questions tagged with their top tag (if any)
  coalesce((
    select count(*) from posts a
    join posts q on q.id = a.parentid
    where a.owneruserid = tu.id and a.posttypeid = 2
      and a.id = q.acceptedanswerid
      and (
        case when ua.top_answer_tags is null or array_length(ua.top_answer_tags,1) = 0 then false
             else array_length(array(select 1 from unnest(coalesce(q.tags, '<>')::text[]) t where t = ua.top_answer_tags[1]),1) > 0
        end
      )
  ),0) as accepted_on_top_tag_questions,
  -- link-derived metric: how many duplicates pointed to this user's questions in last year
  coalesce((
    select count(*) from post_links_expanded ple
    where ple.linktypeid = 3 -- duplicate
      and (ple.postid in (select id from posts where owneruserid = tu.id) or ple.relatedpostid in (select id from posts where owneruserid = tu.id))
  ),0) as duplicates_involving_user_posts,
  -- tag co-occurrence diversity score: number of distinct co-occurring tag pairs involving user's top tag
  coalesce((
    select count(*) from tag_cooccurrence tc
    where ua.top_answer_tags is not null and array_length(ua.top_answer_tags,1) > 0
      and (tc.tag1 = ua.top_answer_tags[1] or tc.tag2 = ua.top_answer_tags[1])
  ),0) as cooccurrence_diversity,
  -- correlation-esque metric: Spearman-like rank approximation between user's answer scores and question hotness (using dense_rank)
  coalesce((
    select round(corr_rank,3) from (
      select corr(r1::double precision, r2::double precision) over () as corr_rank
      from (
        select dense_rank() over (order by a.score desc) as r1,
               dense_rank() over (order by h.hotness_score desc) as r2
        from posts a
        left join hot_questions h on h.question_id = a.parentid
        where a.owneruserid = tu.id and a.posttypeid = 2 and h.hot_rank <= 1000
      ) s
    ) x limit 1
  ),0) as approx_rank_correlation
from top_users tu
left join user_answer_behavior ua on ua.userid = tu.id
left join commenter_clusters cc on cc.userid = tu.id
order by tu.composite_per_day desc
limit 100;