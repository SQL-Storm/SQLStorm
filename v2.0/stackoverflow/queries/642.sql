-- {"query": "642.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3035}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id) as rn_global
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    avg(nullif(p.score, 0)) as avg_nonzero_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.lastactivitydate) as last_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    avg(coalesce(c.score, 0)) as avg_comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where cast(b.tagbased as integer) = 1) as tag_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
q_accepted as (
  select
    q.owneruserid as user_id,
    count(*) as accepted_answers_received
  from posts q
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
  group by q.owneruserid
),
a_accepted as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers_given
  from posts a
  where a.posttypeid = 2
    and exists (
      select 1
      from posts q
      where q.id = a.parentid
        and q.acceptedanswerid = a.id
    )
  group by a.owneruserid
),
vote_agg as (
  select
    v.userid as voter_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.userid is not null
  group by v.userid
),
post_vote_agg as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received
  from posts p
  left join votes v on v.postid = p.id and v.votetypeid in (2,3)
  where p.owneruserid is not null
  group by p.owneruserid
),
tag_exploded as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    lower(trim(tag)) as tagname
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
        then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else array[]::text[] -- keep as-is for dialects that support it; replaceable with ARRAY[] if needed
    end
  ) as t(tag)
),
top_user_tags as (
  select
    t.user_id,
    t.tagname,
    count(*) as tag_posts,
    row_number() over (partition by t.user_id order by count(*) desc, t.tagname) as rn
  from tag_exploded t
  group by t.user_id, t.tagname
),
dupe_closures as (
  select
    ph.postid,
    ph.userid as closer_user_id,
    min(ph.creationdate) as first_close_at,
    count(*) as close_events
  from posthistory ph
  where ph.posthistorytypeid = 10
    and cast(coalesce(nullif(ph.comment, ''), '0') as integer) in (1, 7, 101)
  group by ph.postid, ph.userid
),
post_links_dupes as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links
  from postlinks pl
  group by pl.postid
),
closed_questions as (
  select
    q.id as post_id,
    q.owneruserid as asker_id,
    q.creationdate as question_created_at,
    q.closeddate,
    extract(epoch from (q.closeddate - q.creationdate)) as seconds_to_close
  from posts q
  where q.posttypeid = 1
    and q.closeddate is not null
),
edit_events as (
  select
    ph.userid as editor_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as content_edits,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_applied,
    max(ph.creationdate) as last_edit_at
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
activity_union as (
  select user_activity.user_id from user_activity
  union
  select comment_stats.user_id from comment_stats
  union
  select badge_rollup.user_id from badge_rollup
  union
  select vote_agg.voter_id from vote_agg
  union
  select post_vote_agg.user_id from post_vote_agg
  union
  select closed_questions.asker_id from closed_questions
  union
  select edit_events.editor_id from edit_events
  union
  select dupe_closures.closer_user_id from dupe_closures
),
recent_sample as (
  select
    u.user_id
  from recent_users u
  join activity_union au on au.user_id = u.user_id
  where u.rn_global <= 10000
),
per_user as (
  select
    rs.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ua.q_count,
    ua.a_count,
    ua.avg_nonzero_score,
    ua.total_views,
    ua.last_activity,
    cs.comment_count,
    cs.avg_comment_score,
    cs.last_comment_at,
    br.total_badges,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    br.tag_badges,
    br.last_badge_at,
    qa.accepted_answers_received,
    aa.accepted_answers_given,
    va.upvotes_cast,
    va.downvotes_cast,
    va.favorites_cast,
    va.last_vote_at,
    pva.upvotes_received,
    pva.downvotes_received,
    ee.content_edits,
    ee.suggested_applied,
    ee.last_edit_at,
    tut.tagname as top_tag,
    tut.tag_posts,
    cq_first.seconds_to_close as first_close_seconds,
    dpl.duplicate_links as duplicate_links_from_postlinks,
    ru.websiteurl,
    ru.location,
    rs.user_id as user_id_for_grouping
  from recent_sample rs
  join recent_users ru on ru.user_id = rs.user_id
  left join user_activity ua on ua.user_id = rs.user_id
  left join comment_stats cs on cs.user_id = rs.user_id
  left join badge_rollup br on br.user_id = rs.user_id
  left join q_accepted qa on qa.user_id = rs.user_id
  left join a_accepted aa on aa.user_id = rs.user_id
  left join vote_agg va on va.voter_id = rs.user_id
  left join post_vote_agg pva on pva.user_id = rs.user_id
  left join edit_events ee on ee.editor_id = rs.user_id
  left join top_user_tags tut on tut.user_id = rs.user_id and tut.rn = 1
  left join lateral (
    select min(cq.seconds_to_close) as seconds_to_close
    from closed_questions cq
    where cq.asker_id = rs.user_id
  ) cq_first on true
  left join lateral (
    select sum(pld.duplicate_links) as duplicate_links
    from posts q
    left join post_links_dupes pld on pld.postid = q.id
    where q.posttypeid = 1 and q.owneruserid = rs.user_id
  ) dpl on true
  group by
    rs.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ua.q_count,
    ua.a_count,
    ua.avg_nonzero_score,
    ua.total_views,
    ua.last_activity,
    cs.comment_count,
    cs.avg_comment_score,
    cs.last_comment_at,
    br.total_badges,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    br.tag_badges,
    br.last_badge_at,
    qa.accepted_answers_received,
    aa.accepted_answers_given,
    va.upvotes_cast,
    va.downvotes_cast,
    va.favorites_cast,
    va.last_vote_at,
    pva.upvotes_received,
    pva.downvotes_received,
    ee.content_edits,
    ee.suggested_applied,
    ee.last_edit_at,
    tut.tagname,
    tut.tag_posts,
    cq_first.seconds_to_close,
    dpl.duplicate_links,
    ru.websiteurl,
    ru.location,
    rs.user_id
),
scored as (
  select
    p.user_id,
    p.displayname,
    p.reputation,
    p.cohort_month,
    p.q_count,
    p.a_count,
    p.avg_nonzero_score,
    p.total_views,
    p.last_activity,
    p.comment_count,
    p.avg_comment_score,
    p.last_comment_at,
    p.total_badges,
    p.gold_badges,
    p.silver_badges,
    p.bronze_badges,
    p.tag_badges,
    p.last_badge_at,
    p.accepted_answers_received,
    p.accepted_answers_given,
    p.upvotes_cast,
    p.downvotes_cast,
    p.favorites_cast,
    p.last_vote_at,
    p.upvotes_received,
    p.downvotes_received,
    p.content_edits,
    p.suggested_applied,
    p.last_edit_at,
    p.top_tag,
    p.tag_posts,
    p.first_close_seconds,
    p.duplicate_links_from_postlinks,
    p.websiteurl,
    p.location,
    coalesce(p.q_count,0) + coalesce(p.a_count,0) as total_posts,
    coalesce(p.upvotes_received,0) - coalesce(p.downvotes_received,0) as net_votes_received,
    coalesce(p.upvotes_cast,0) - coalesce(p.downvotes_cast,0) as net_votes_cast,
    case
      when coalesce(p.a_count,0) = 0 then null
      else round(100.0 * cast(coalesce(p.accepted_answers_given,0) as numeric) / nullif(p.a_count,0), 2)
    end as answer_accept_rate_pct,
    case
      when coalesce(p.q_count,0) = 0 then null
      else round(100.0 * cast(coalesce(p.accepted_answers_received,0) as numeric) / nullif(p.q_count,0), 2)
    end as question_accept_rate_pct,
    round(
      cast(coalesce(p.reputation,0) as numeric)
      + 2.0 * coalesce(p.total_views,0)
      + 5.0 * coalesce(p.upvotes_received,0)
      - 7.0 * coalesce(p.downvotes_received,0)
      + 10.0 * coalesce(p.gold_badges,0)
      + 5.0 * coalesce(p.silver_badges,0)
      + 2.0 * coalesce(p.bronze_badges,0)
      + 1.5 * coalesce(p.comment_count,0)
      + 25.0 * coalesce(p.content_edits,0)
      - 50.0 * (case when coalesce(p.first_close_seconds,0) < 3600 then 1 else 0 end)
      + 15.0 * coalesce(p.duplicate_links_from_postlinks,0)
    , 2) as activity_score
  from per_user p
),
ranked as (
  select
    s.*,
    row_number() over (order by s.activity_score desc nulls last, s.net_votes_received desc, s.total_posts desc, s.user_id) as rk_overall,
    dense_rank() over (partition by date_trunc('month', s.cohort_month) order by s.activity_score desc nulls last) as rk_in_cohort,
    percent_rank() over (order by s.activity_score) as pct_rank,
    ntile(10) over (order by s.activity_score desc nulls last) as decile
  from scored s
),
stringified as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    coalesce(r.top_tag, 'none') as top_tag,
    r.total_posts,
    r.activity_score,
    r.rk_overall,
    r.rk_in_cohort,
    r.decile,
    r.pct_rank,
    r.net_votes_received,
    r.net_votes_cast,
    r.answer_accept_rate_pct,
    r.question_accept_rate_pct,
    r.last_activity,
    r.last_vote_at,
    r.last_edit_at,
    r.first_close_seconds,
    r.duplicate_links_from_postlinks,
    r.gold_badges, r.silver_badges, r.bronze_badges,
    r.comment_count,
    case
      when r.websiteurl is null or lower(r.websiteurl) like '%stackoverflow%' then null
      else trim(both from r.websiteurl)
    end as cleaned_website,
    case when r.location is not null and lower(r.location) like '%remote%' then 'remote'
         when r.location is not null and (lower(r.location) like '%usa%' or lower(r.location) like '%united states%') then 'usa'
         when r.location is null or trim(both from r.location) = '' then 'unknown'
         else 'other'
    end as location_bucket
  from ranked r
),
null_sentinel as (
  select
    s.*,
    coalesce(cast(s.answer_accept_rate_pct as text), 'NA') as answer_accept_rate_txt,
    coalesce(cast(s.question_accept_rate_pct as text), 'NA') as question_accept_rate_txt
  from stringified s
)
select
  ns.user_id,
  ns.displayname,
  ns.reputation,
  ns.top_tag,
  ns.total_posts,
  ns.activity_score,
  ns.rk_overall,
  ns.rk_in_cohort,
  ns.decile,
  ns.pct_rank,
  ns.net_votes_received,
  ns.net_votes_cast,
  ns.answer_accept_rate_txt,
  ns.question_accept_rate_txt,
  ns.last_activity,
  ns.last_vote_at,
  ns.last_edit_at,
  ns.first_close_seconds,
  ns.duplicate_links_from_postlinks,
  ns.gold_badges, ns.silver_badges, ns.bronze_badges,
  ns.comment_count,
  ns.cleaned_website,
  ns.location_bucket
from null_sentinel ns
where
  (ns.activity_score is not null and ns.activity_score > 0)
  and (
    ns.decile in (1,2,3)
    or (ns.net_votes_received >= all (
      select coalesce(pva.upvotes_received,0) - coalesce(pva.downvotes_received,0)
      from post_vote_agg pva
      where pva.user_id is not null
    ))
  )
order by ns.activity_score desc, ns.user_id
limit 500;