-- {"query": "95.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2055} 
with
-- recent active questions with tag normalization and computed quality score
RecentQuestions as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    p.viewcount,
    coalesce(p.answercount,0) as answercount,
    coalesce(p.score,0) as score,
    coalesce(p.favoritecount,0) as favs,
    -- normalize tags into rows: tags are like '<tag1><tag2>'
    regexp_split_to_table(substring(p.tags from 2 for greatest(char_length(p.tags)-2,0)), '><') as tag
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '180 days'
),
-- aggregate user-level recent activity: reputation trend, questions asked, answers given
UserActivity as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    sum(case when rq.owneruserid = u.id then 1 else 0 end) as recent_questions,
    sum(case when a.parentid is not null and a.owneruserid = u.id and a.creationdate >= now() - interval '180 days' then 1 else 0 end) as recent_answers,
    count(distinct b.id) filter (where b.date >= now() - interval '365 days') as badges_last_year,
    -- reputation change approximation: users created before window get delta from min/max rep via correlated subquery (if history tracked externally, fallback to zero)
    coalesce((
      select greatest(0, max(reputation)-min(reputation))
      from users u2
      where u2.id = u.id
    ),0) as rep_delta
  from users u
  left join recentquestions rq on rq.owneruserid = u.id
  left join posts a on a.posttypeid = 2 and a.parentid is not null and a.owneruserid = u.id and a.creationdate >= now() - interval '180 days'
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation
),
-- compute post-level metrics including correlated subqueries for latest comment and last edit history
PostEnriched as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.answercount,
    p.tags,
    -- number of distinct commenters
    (select count(distinct coalesce(c.userid, -1)) from comments c where c.postid = p.id) as distinct_commenters,
    -- latest comment text (may be null)
    (select c.text from comments c where c.postid = p.id order by c.creationdate desc limit 1) as latest_comment,
    -- last post history type name (may be null)
    (select pht.name from posthistory ph join posthistorytypes pht on ph.posthistorytypeid = pht.id where ph.postid = p.id order by ph.creationdate desc limit 1) as last_history,
    -- average answer score for answers to this question (null if none)
    (select avg(coalesce(a.score,0)) from posts a where a.parentid = p.id and a.posttypeid = 2) as avg_answer_score,
    -- boolean-ish: has accepted answer from same owner as question asker (correlated)
    case when p.acceptedanswerid is not null and exists (
      select 1 from posts aa where aa.id = p.acceptedanswerid and aa.owneruserid = p.owneruserid
    ) then 1 else 0 end as accepted_by_same_user,
    -- heuristic quality score combining many signals
    (coalesce(p.score,0) * 2.0
     + coalesce((select avg(coalesce(a.score,0)) from posts a where a.parentid = p.id and a.posttypeid = 2),0) * 1.5
     + greatest(coalesce(p.viewcount,0)/nullif(greatest(coalesce(p.answercount,0),1),0),0)::float * 0.1
     + coalesce((select count(*) from comments c where c.postid = p.id),0) * 0.2
     + coalesce(p.favoritecount,0) * 0.5
     - (case when p.closeddate is not null then 10 else 0 end)
    ) as quality_score
  from posts p
  where p.posttypeid = 1
),
-- windowed ranking per tag and global rank
TagRanked as (
  select
    rq.tag,
    pe.*,
    row_number() over (partition by rq.tag order by pe.quality_score desc nulls last, pe.viewcount desc) as tag_rank,
    dense_rank() over (order by pe.quality_score desc nulls last) as global_rank
  from recentquestions rq
  join postenriched pe on pe.id = rq.id
),
-- compute cross-links and duplication chains using postlinks (outer joins to include lonely posts)
LinkGraph as (
  select
    p.id,
    p.title,
    count(pl.id) filter (where pl.linktypeid = 1) as outgoing_links,
    count(pl.id) filter (where pl.linktypeid = 3) as outgoing_duplicates,
    count(pl2.id) filter (where pl2.linktypeid = 1) as incoming_links,
    array_agg(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) filter (where pl.linktypeid = 3) as duplicate_targets
  from posts p
  left join postlinks pl on pl.postid = p.id
  left join postlinks pl2 on pl2.relatedpostid = p.id
  where p.posttypeid in (1,2)
  group by p.id, p.title
),
-- expensive string/regex operations and complex predicates for stress
TagFingerprint as (
  select
    t.tagname,
    t.count,
    lower(regexp_replace(tagname, '[^a-z0-9]+', '', 'g')) as fingerprint,
    substring(md5(tagname || '|' || coalesce((select max(creationdate) from posts where tags ilike '%'|| '<' || tagname || '>' || '%' ), now())::text) from 1 for 8) as shorthash
  from tags t
),
-- final combined result picking interesting rows with set operators and filtering
TopCombos as (
  select distinct on (tr.tag, tr.id)
    tr.tag,
    tr.id as question_id,
    tr.title,
    tr.creationdate,
    tr.owneruserid,
    ua.displayname as owner_name,
    ua.reputation,
    tr.quality_score,
    tr.tag_rank,
    tr.global_rank,
    lg.outgoing_links,
    lg.incoming_links,
    lg.outgoing_duplicates,
    tg.fingerprint,
    tg.shorthash,
    -- categorize: hot, trending, stale
    case
      when tr.quality_score >= (select percentile_cont(0.9) within group (order by quality_score) from postenriched) then 'hot'
      when tr.creationdate >= now() - interval '14 days' and tr.quality_score >= (select avg(quality_score) from postenriched) then 'trending'
      when tr.creationdate < now() - interval '90 days' and tr.answercount = 0 then 'stale_unanswered'
      else 'normal'
    end as category
  from tagranked tr
  left join useractivity ua on ua.userid = tr.owneruserid
  left join linkgraph lg on lg.id = tr.id
  left join tagfingerprint tg on tg.tagname = tr.tag
  where tr.tag is not null
    and (tr.quality_score is not null OR tr.viewcount > 1000)
)
-- final projection with union to introduce set operator variety: include top combos plus synthetic anomalies (using EXCEPT to remove duplicates)
select *
from (
  select
    tag,
    question_id,
    title,
    creationdate,
    owneruserid,
    owner_name,
    reputation,
    round(quality_score::numeric,3) as quality_score,
    tag_rank,
    global_rank,
    coalesce(outgoing_links,0) as outgoing_links,
    coalesce(incoming_links,0) as incoming_links,
    coalesce(outgoing_duplicates,0) as outgoing_duplicates,
    fingerprint,
    shorthash,
    category
  from topcombos
  where category in ('hot','trending')
  order by tag, tag_rank
  limit 200

  union

  select
    tc.tag,
    tc.question_id,
    left(tc.title, 120) as title,
    tc.creationdate,
    tc.owneruserid,
    tc.owner_name,
    tc.reputation,
    tc.quality_score,
    tc.tag_rank,
    tc.global_rank,
    tc.outgoing_links,
    tc.incoming_links,
    tc.outgoing_duplicates,
    tc.fingerprint,
    tc.shorthash,
    tc.category
  from topcombos tc
  where tc.category = 'stale_unanswered'
  order by tc.creationdate asc
  limit 100

  except

  select
    tag,
    question_id,
    title,
    creationdate,
    owneruserid,
    owner_name,
    reputation,
    round(quality_score::numeric,3) as quality_score,
    tag_rank,
    global_rank,
    outgoing_links,
    incoming_links,
    outgoing_duplicates,
    fingerprint,
    shorthash,
    category
  from topcombos
  where owner_name is null or owner_name = ''
) as final
order by category desc, quality_score desc, creationdate desc
limit 250;