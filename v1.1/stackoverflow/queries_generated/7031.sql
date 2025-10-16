-- {"query": "7031.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2576} 
with
-- active users with weighted reputation trend and recent activity window
user_activity as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    greatest(0, extract(epoch from (now() - u.lastaccessdate))/86400) as days_since_last_access,
    -- penalize old accounts mildly, reward recent access
    (u.reputation * 0.6)::numeric
      + (case when u.lastaccessdate > now() - interval '30 days' then 100 else 0 end)
      + (case when u.creationdate > now() - interval '365 days' then 50 else 0 end) as activity_score
  from users u
  where u.reputation is not null
),
-- compute per-question aggregates including tag parsing and answer stats
questions as (
  select
    p.id as question_id,
    p.owneruserid,
    p.title,
    p.creationdate,
    p.score,
    coalesce(p.viewcount,0) as viewcount,
    p.answercount,
    p.tags,
    -- split tags into array, handle null/empty
    case when p.tags is null or p.tags = '' then array[]::varchar[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array,
    -- count distinct commenters on question
    (select count(distinct c.userid) from comments c where c.postid = p.id) as question_commenters,
    -- latest activity across answers and comments (correlated subquery)
    (select max(tmax) from (
        select max(coalesce(a.lastactivitydate, a.creationdate)) as tmax from posts a where a.parentid = p.id
        union all
        select max(c.creationdate) from comments c where c.postid = p.id
        union all
        select p.lastactivitydate
    ) x) as overall_last_activity
  from posts p
  where p.posttypeid = 1
),
-- heavy analytics on answers including acceptance, score distribution, and a moving-window rank per question
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid,
    a.creationdate,
    a.score,
    a.body,
    a.lastactivitydate,
    case when q.acceptedanswerid = a.id then true else false end as is_accepted,
    -- text complexity proxy: length + number of code blocks
    (char_length(coalesce(a.body,'')) + (char_length(coalesce(a.body,'')) - char_length(replace(coalesce(a.body,''), '<code>','')))/6)::int as complexity_score,
    -- position by score and recentness per question
    row_number() over (partition by a.parentid order by a.score desc, a.creationdate asc) as score_rank,
    rank() over (partition by a.parentid order by a.lastactivitydate desc nulls last) as recent_rank
  from posts a
  left join posts q on q.id = a.parentid
  where a.posttypeid = 2
),
-- votes summarized per post with pivot-like counts and recent vote intensity
post_votes as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 5) as favorites,
    count(*) filter (where v.votetypeid = 1) as accepts,
    count(*) as total_votes,
    sum(case when v.creationdate > now() - interval '30 days' then 1 else 0 end) as recent_votes_30d
  from votes v
  group by v.postid
),
-- link closure/duplication relationships and distance-to-duplicate cycles
post_links_agg as (
  select
    pl.postid,
    count(*) filter (where lt.name = 'Duplicate' or pl.linktypeid = 3) as duplicates_out,
    count(*) filter (where lt.name = 'Linked' or pl.linktypeid = 1) as links_out,
    array_agg(distinct pl.relatedpostid) filter (where pl.relatedpostid is not null) as related_posts
  from postlinks pl
  left join linktypes lt on lt.id = pl.linktypeid
  group by pl.postid
),
-- badge velocity per user last year
badge_velocity as (
  select
    b.userid,
    count(*) filter (where b.date > now() - interval '365 days') as badges_last_year,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges
  from badges b
  group by b.userid
),
-- assemble question-level detail combining many pieces
question_details as (
  select
    q.*,
    ua.displayname as owner_name,
    ua.reputation as owner_reputation,
    bv.badges_last_year,
    pv.upvotes, pv.downvotes, pv.favorites, pv.total_votes,
    pla.duplicates_out, pla.links_out,
    -- compute an engagement index with null-handling and non-linear scaling
    (
      least(1e6, (coalesce(q.viewcount,0)^0.5)::numeric * 2
        + coalesce(q.answercount,0)*100
        + coalesce(q.question_commenters,0)*50
        + (coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0))*30
        + coalesce(bv.badges_last_year,0)*10)
    )::numeric as engagement_index
  from questions q
  left join users ua on ua.id = q.owneruserid
  left join badge_velocity bv on bv.userid = q.owneruserid
  left join post_votes pv on pv.postid = q.question_id
  left join post_links_agg pla on pla.postid = q.question_id
),
-- top contributing answerers per tag (explode tags)
question_tags as (
  select
    qd.question_id,
    tag,
    qd.title,
    qd.owneruserid,
    qd.engagement_index
  from question_details qd
  cross join lateral (
    select unnest(qd.tag_array) as tag
  ) t
),
-- top N answerers per tag by aggregated answer score (complex correlated aggregation)
tag_answerers as (
  select
    qt.tag,
    a.owneruserid as answerer_id,
    u.displayname as answerer_name,
    sum(a.score) as total_answer_score,
    count(*) as answers_count,
    avg(a.complexity_score) as avg_complexity,
    max(case when a.is_accepted then 1 else 0 end) as has_accepted_any,
    row_number() over (partition by qt.tag order by sum(a.score) desc nulls last, count(*) desc) as tag_rank
  from question_tags qt
  join answers a on a.question_id = qt.question_id
  left join users u on u.id = a.owneruserid
  group by qt.tag, a.owneruserid, u.displayname
),
-- compute global aggregates and percentiles
global_stats as (
  select
    (select percentile_cont(0.50) within group (order by engagement_index) from question_details) as median_engagement,
    (select percentile_cont(0.90) within group (order by engagement_index) from question_details) as p90_engagement,
    (select count(*) from posts where posttypeid = 1) as total_questions,
    (select count(*) from posts where posttypeid = 2) as total_answers
)
-- final select: heavy statistical join, windowing, set operators, correlated subqueries and filters
select
  qd.question_id,
  qd.title,
  left(coalesce(qd.title,'<no title>'), 120) as short_title,
  qd.owner_name,
  qd.owner_reputation,
  qd.engagement_index,
  gs.median_engagement,
  gs.p90_engagement,
  case
    when qd.engagement_index >= gs.p90_engagement then 'top10%'
    when qd.engagement_index >= gs.median_engagement then 'above_median'
    else 'below_median'
  end as engagement_bucket,
  coalesce(pv.upvotes,0) as upvotes,
  coalesce(pv.downvotes,0) as downvotes,
  coalesce(pv.total_votes,0) as total_votes,
  coalesce(qa.top_answer_id, null) as top_answer_id,
  qa.top_answer_score,
  qa.top_answer_owner,
  qa.top_answer_complexity,
  -- correlated: is there a duplicate pointing to a higher-score question?
  exists (
    select 1 from postlinks pl
    join posts rp on rp.id = pl.relatedpostid
    where pl.postid = qd.question_id and (pl.linktypeid = 3 or (select name from linktypes where id = pl.linktypeid) = 'Duplicate')
      and coalesce(rp.score,0) > coalesce(qd.score,0)
    limit 1
  ) as has_higher_scored_duplicate,
  -- top 3 answerers for the first tag (if exists) using set operator union all to include a fallback null row
  (select json_agg(row_to_json(t)) from (
     select ta.answerer_id, ta.answerer_name, ta.total_answer_score, ta.answers_count, ta.avg_complexity
     from tag_answerers ta
     where ta.tag = (select tag from question_tags qt where qt.question_id = qd.question_id limit 1)
       and ta.tag_rank <= 3
     union all
     select null, null, null, null, null
     limit 3
  ) t) as top_answerers_first_tag,
  -- window function: ranking by engagement among same owner
  rank() over (partition by qd.owneruserid order by qd.engagement_index desc) as owner_question_rank,
  -- textual fuzz: normalized tag list as string and a checksum-like hash
  (select string_agg(distinct t.tag, ',') from question_tags t where t.question_id = qd.question_id) as tag_list,
  mod(abs(hashtext(coalesce((select string_agg(distinct t.tag, ',') from question_tags t where t.question_id = qd.question_id), qd.title))), 1000000) as quick_hash,
  -- conditional complex expression with null logic combining favorites, accepts, and duplicates
  case
    when coalesce(pv.favorites,0) > 10 and coalesce(pla.duplicates_out,0) >= 1 then 'popular_but_duplicated'
    when coalesce(pv.favorites,0) > 10 then 'popular'
    when coalesce(pv.total_votes,0) = 0 and qd.answercount = 0 then 'neglected'
    else 'normal'
  end as status_label
from question_details qd
left join global_stats gs on true
left join post_votes pv on pv.postid = qd.question_id
left join post_links_agg pla on pla.postid = qd.question_id
left join lateral (
  -- pick top answer per question using a mixture of score, acceptance, recency and complexity
  select a.answer_id as top_answer_id, a.score as top_answer_score, a.owneruserid as top_answer_owner, a.complexity_score as top_answer_complexity
  from answers a
  where a.question_id = qd.question_id
  order by (case when a.is_accepted then 1 else 0 end) desc,
           a.score desc nulls last,
           a.recent_rank asc,
           a.complexity_score desc
  limit 1
) qa on true
where qd.engagement_index is not null
order by qd.engagement_index desc NULLS LAST
limit 200;