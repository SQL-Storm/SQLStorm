-- {"query": "7039.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1814} 
with
-- recent activity per post with windowing and string mangling
RecentActivity as (
  select
    p.id as post_id,
    p.posttypeid,
    coalesce(p.title, substring(p.body from 1 for 120)) as headline,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.tags,
    -- extract first tag or null
    nullif(regexp_replace(coalesce(p.tags,''), '^<([^>]+)>(?:.*)$', '\1'), '') as first_tag,
    -- compact hash-like signature for grouping
    lower(md5(coalesce(p.title,'') || '|' || coalesce(p.tags,''))) as signature,
    row_number() over (partition by p.owneruserid order by p.lastactivitydate desc nulls last, p.score desc) as rn_user_post
  from posts p
),
-- derive user aggregates including badge distributions and activity skew
UserAgg as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate,
    count(distinct b.id) filter (where b.class = 1) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) as bronze_badges,
    -- bias score: weighted posts by recency (exponential decay)
    sum(coalesce(p.score,0) * exp(- greatest(0, extract(epoch from (now()-coalesce(p.lastactivitydate,p.creationdate)))/ (60*60*24*180)) )) as recency_weighted_score,
    -- ratio safe-guarded
    nullif(u.upvotes,0) as upvotes_nonzero,
    u.downvotes,
    case when u.views > 0 then round( (u.upvotes::numeric - u.downvotes)::numeric / greatest(1,u.views)::numeric, 6) else null end as vote_per_view
  from users u
  left join badges b on b.userid = u.id
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.upvotes, u.downvotes, u.views
),
-- top-level question-answer linkage with correlated subqueries and exists checks
QAs as (
  select
    q.id as question_id,
    q.acceptedanswerid,
    q.answercount,
    q.score as q_score,
    a.id as answer_id,
    a.score as a_score,
    a.owneruserid as a_owner,
    a.creationdate as a_created,
    -- correlated: count of comments on answer more recent than question creation
    (select count(*) from comments c where c.postid = a.id and c.creationdate > q.creationdate) as recent_comments_on_answer,
    -- correlated: top 3 voters (by vote type and date) for answer aggregated into csv
    (select string_agg(vw.voter_summary, ';' order by vw.vote_count desc nulls last)
     from (
        select vt.name || ':' || count(*) || '@' || to_char(min(v.creationdate),'YYYY-MM-DD') as voter_summary,
               count(*) as vote_count
        from votes v
        join votetypes vt on vt.id = v.votetypeid
        where v.postid = a.id
        group by vt.name
        order by vote_count desc
        limit 3
     ) vw
    ) as top_vote_summary
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
-- compute network of linked posts and duplicate chains using recursive CTE
RecursiveLinks as (
  select pl.postid, pl.relatedpostid, pl.linktypeid, 1 as depth, array[pl.postid, pl.relatedpostid] as path
  from postlinks pl
  where pl.postid is not null
  union all
  select r.postid, pl.relatedpostid, pl.linktypeid, r.depth+1, r.path || pl.relatedpostid
  from RecursiveLinks r
  join postlinks pl on pl.postid = r.relatedpostid
  where not pl.relatedpostid = any(r.path) and r.depth < 6
),
-- compute per-question complex score using set operators and NULL logic
QuestionComplexScore as (
  select
    p.id as question_id,
    p.title,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    -- extenuated score: base + ln(viewcount+1) * sign + badge bonus from owner
    (p.score
     + coalesce(ln(greatest(p.viewcount,1)) , 0) * sign(p.score + 0.00001)
     + coalesce( (select 5*count(*) from badges b where b.userid = p.owneruserid and b.class = 1), 0)
     - coalesce( (select count(*) from posthistory ph where ph.postid = p.id and ph.posthistorytypeid in (10,12) ), 0) * 0.5
    ) as ext_score,
    -- duplication depth and distinct chains
    (select count(distinct rl.path[1]) from recursiveLinks rl where rl.postid = p.id and rl.linktypeid = 3) as duplicate_chains,
    -- existence of tag 'sql' or similar via ilike and tag parsing
    case when p.tags ilike '%<sql>%' then 1 else 0 end as has_sql_tag,
    -- compute tagset fingerprint: sorted unique tags collapsed
    (select string_agg(distinct tag, ',' order by tag)
     from unnest(string_to_array(substring(coalesce(p.tags,''),2, greatest(length(coalesce(p.tags,''))-2,0)), '><')) tag
    ) as tag_fingerprint
  from posts p
  where p.posttypeid = 1
),
-- final picks: combine everything, heavy expressions, left joins, aggregates and set operators
FinalPick as (
  select
    ra.post_id,
    ra.posttypeid,
    ra.headline,
    ra.owneruserid,
    ra.signature,
    ua.displayname,
    ua.reputation,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    qs.ext_score,
    qs.duplicate_chains,
    qs.has_sql_tag,
    qa.answer_id,
    qa.a_score,
    qa.recent_comments_on_answer,
    qa.top_vote_summary,
    -- composite rank using window functions and coalesce
    rank() over (partition by coalesce(ua.reputation::text,'0') order by qs.ext_score desc nulls last, ra.lastactivitydate desc nulls last) as composite_rank
  from RecentActivity ra
  left join UserAgg ua on ua.user_id = ra.owneruserid
  left join QuestionComplexScore qs on qs.question_id = ra.post_id
  left join QAs qa on qa.question_id = ra.post_id
  where ra.rn_user_post <= 5
)
select
  fp.*,
  -- correlated scalar: whether owner answered their own question (exists)
  exists (select 1 from posts p where p.parentid = fp.post_id and p.owneruserid = fp.owneruserid) as owner_self_answered,
  -- show delta days between last activity and user last access (can be negative if user last access in future)
  extract(epoch from (coalesce(fp.lastactivitydate, fp.creationdate) - coalesce(u.lastaccessdate, now()))) / 86400.0 as days_since_user_last_access,
  -- include asymmetric set operator example: questions that are in top ext_score but not in top recency-weighted user posts
  case when fp.post_id in (
       select question_id from QuestionComplexScore qcs
       except
       select post_id from RecentActivity where signature = fp.signature
    ) then 'IN_TOP_SCORE_BUT_NOT_IN_RECENT' else 'OK' end as score_recency_diff
from FinalPick fp
left join users u on u.id = fp.owneruserid
where (fp.ext_score is not null and fp.ext_score > 1)
  or (fp.has_sql_tag = 1)
order by fp.composite_rank asc, fp.ext_score desc nulls last
limit 200;