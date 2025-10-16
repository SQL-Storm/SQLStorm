-- {"query": "158.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2184} 
with
-- explode tags from Posts (questions only)
question_tags as (
  select p.id as post_id, trim(t) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags from 2 for char_length(coalesce(p.tags,'')) - 2), '><')) as t
  ) s
  where p.posttypeid = 1 and p.tags is not null
),

-- basic per-question aggregates
question_aggs as (
  select
    q.id,
    q.title,
    q.owneruserid,
    q.creationdate,
    q.lastactivitydate,
    q.score,
    q.viewcount,
    coalesce(q.answercount,0) as answercount,
    coalesce(q.favoritecount,0) as favoritecount,
    -- avg answer score for answers to this question
    (select avg(a.score::numeric) from posts a where a.parentid = q.id and a.posttypeid = 2) as avg_answer_score,
    -- number of distinct answerers (excluding community)
    (select count(distinct a.owneruserid) from posts a where a.parentid = q.id and a.posttypeid = 2 and a.owneruserid is not null and a.owneruserid <> -1) as distinct_answerers,
    -- time to first answer (in seconds)
    (select extract(epoch from min(a.creationdate) - q.creationdate)
     from posts a where a.parentid = q.id and a.posttypeid = 2 and a.creationdate is not null) as secs_to_first_answer
  from posts q
  where q.posttypeid = 1
),

-- per-tag aggregated metrics
tag_stats as (
  select
    t.tag,
    count(distinct qt.post_id) as questions,
    sum(q.score) filter (where q.score > 0) as positive_score_sum,
    avg(q.viewcount) as avg_views,
    percentile_cont(0.5) within group (order by q.score) as median_score,
    -- hottest questions: most recent activity weighted by score
    max((extract(epoch from q.lastactivitydate)) + coalesce(q.score,0)*3600) as hotness_score
  from question_tags qt
  join question_aggs q on q.id = qt.post_id
  group by t.tag
),

-- user-level engagement: posts, answers, comments, votes received
user_posts as (
  select u.id as userid,
    u.displayname,
    count(p.id) filter (where p.posttypeid = 1) as questions,
    count(p.id) filter (where p.posttypeid = 2) as answers,
    sum(p.score) filter (where p.posttypeid in (1,2)) as total_post_score,
    max(u.reputation) as reputation,
    -- fraction of answers accepted
    (select count(*)::numeric from posts a where a.posttypeid = 2 and a.owneruserid = u.id and exists (
       select 1 from posts q where q.acceptedanswerid = a.id
    )) as accepted_answers_count
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname
),

-- per-post comment and vote mini-aggregates (including correlated subqueries)
post_micro as (
  select p.id,
    p.posttypeid,
    p.parentid,
    p.title,
    p.creationdate,
    p.owneruserid,
    coalesce((select count(*) from comments c where c.postid = p.id),0) as comment_count,
    coalesce((select count(*) filter (where v.votetypeid = 2) from votes v where v.postid = p.id),0) as upvotes,
    coalesce((select count(*) filter (where v.votetypeid = 3) from votes v where v.postid = p.id),0) as downvotes,
    -- last comment text (may be null)
    (select c.text from comments c where c.postid = p.id order by c.creationdate desc limit 1) as last_comment_text,
    -- concatenated snippet of first 120 chars of body (handling nulls)
    left(coalesce(p.body,''), 120) as body_snippet
  from posts p
),

-- identify posts with anomalous score-to-view ratios using window functions
anomalies as (
  select
    p.id,
    p.title,
    p.viewcount,
    p.score,
    case when p.viewcount > 0 then (p.score::numeric / nullif(p.viewcount,0)) else null end as score_view_ratio,
    ntile(100) over (order by case when p.viewcount > 0 then (p.score::numeric / nullif(p.viewcount,0)) else -1 end desc) as percentile_rank_ratio
  from posts p
  where p.posttypeid in (1,2) and p.viewcount is not null
),

-- combine a "leaderboard" of tags joined to top contributors for the tag
tag_leaders as (
  select
    ts.tag,
    ts.questions,
    ts.avg_views,
    ts.median_score,
    -- top contributor to this tag by number of answers on questions with this tag
    (select u.displayname
     from users u
     join posts a on a.owneruserid = u.id and a.posttypeid = 2
     join question_tags qt2 on qt2.post_id = a.parentid
     where qt2.tag = ts.tag
     group by u.id, u.displayname
     order by count(*) desc, max(a.score) desc
     limit 1
    ) as top_answerer,
    -- count of distinct answerers on tag
    (select count(distinct a.owneruserid)
     from posts a
     join question_tags qt2 on qt2.post_id = a.parentid
     where a.posttypeid = 2 and qt2.tag = ts.tag and a.owneruserid is not null
    ) as distinct_answerers
  from tag_stats ts
  where ts.questions > 5
),

-- recent complex activity window combining edits, votes, comments across posts
recent_activity as (
  select
    p.id as post_id,
    p.title,
    greatest(p.creationdate, coalesce(ph.max_edit, '1970-01-01'::timestamp), coalesce(v.max_vote, '1970-01-01'::timestamp), coalesce(c.max_comment, '1970-01-01'::timestamp)) as most_recent_activity,
    ph.edits,
    v.votes,
    c.comments,
    -- a heuristic "activity score"
    (coalesce(ph.edits,0)*2 + coalesce(v.votes,0)*1 + coalesce(c.comments,0)*1.5 + coalesce(p.score,0)) as activity_score
  from posts p
  left join (
    select postid, count(*) as edits, max(creationdate) as max_edit
    from posthistory ph group by postid
  ) ph on ph.postid = p.id
  left join (
    select postid, count(*) as votes, max(creationdate) as max_vote
    from votes v group by postid
  ) v on v.postid = p.id
  left join (
    select postid, count(*) as comments, max(creationdate) as max_comment
    from comments c group by postid
  ) c on c.postid = p.id
),

-- a final combined result that exercises many constructs
final_combined as (
  select
    p.id as post_id,
    p.posttypeid,
    p.title,
    u.displayname as owner,
    qp.body_snippet,
    qp.last_comment_text,
    qa.answercount,
    qa.avg_answer_score,
    pm.comment_count,
    pm.upvotes,
    pm.downvotes,
    ra.activity_score,
    an.score_view_ratio,
    tl.tag,
    tl.top_answerer,
    -- a complex expression mixing null logic and string ops
    case
      when p.title is null then 'NO TITLE'
      when length(p.title) > 80 then left(p.title,77) || '...'
      else p.title
    end as title_brief,
    -- create a synthetic "quality index"
    round(
      (
        coalesce(p.score,0)*2
        + coalesce(qa.avg_answer_score,0)*3
        + coalesce(pm.upvotes,0)*1.5
        - coalesce(pm.downvotes,0)*1.5
        + coalesce(ra.activity_score,0)/10
        - coalesce(an.score_view_ratio,0)
      )::numeric
      ,2) as quality_index
  from posts p
  left join users u on u.id = p.owneruserid
  left join question_aggs qa on qa.id = p.id
  left join post_micro pm on pm.id = p.id
  left join recent_activity ra on ra.post_id = p.id
  left join anomalies an on an.id = p.id
  left join lateral (
    select body_snippet, last_comment_text from post_micro where id = p.id
  ) qp on true
  left join lateral (
    -- pick a representative tag for questions, null for non-questions
    select tag from question_tags qt where qt.post_id = p.id order by tag limit 1
  ) tlh on true
  left join tag_leaders tl on tl.tag = tlh.tag
  where p.creationdate >= now() - interval '5 years' -- limit scope
)

select *
from final_combined
where quality_index is not null
order by quality_index desc nulls last, activity_score desc
limit 200;