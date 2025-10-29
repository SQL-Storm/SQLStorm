-- {"query": "96.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3677} 
with recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.closeddate,
    p.contentlicense,
    row_number() over (partition by p.owneruserid order by p.creationdate desc, p.id desc) as rn_owner,
    row_number() over (partition by p.posttypeid order by p.score desc, p.viewcount desc, p.id) as rn_type
  from posts p
  where p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '180 days' from posts)
),
user_badge_summary as (
  select
    u.id as userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
    and b.date >= (select coalesce(min(creationdate), now() - interval '10 years') from posts) -- anti-skew
  group by u.id
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by v.postid
),
comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
    avg(nullif(c.score, 0)) as avg_nonzero_comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
postlink_agg as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
    count(*) as total_links,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  group by pl.postid
),
tag_split as (
  select
    p.id as postid,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and length(p.tags) > 2
),
tag_rank as (
  select
    ts.postid,
    ts.tagname,
    t.count as tag_global_usage,
    row_number() over (partition by ts.postid order by t.count desc nulls last, ts.tagname) as tag_rank_in_post
  from tag_split ts
  left join tags t
    on lower(ts.tagname) = lower(t.tagname)
),
owner_activity as (
  select
    u.id as userid,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    avg(nullif(p.score,0)) as avg_nonzero_score,
    percentile_cont(0.5) within group (order by p.score) as median_score,
    max(p.lastactivitydate) as last_activity,
    sum(coalesce(p.viewcount,0)) as total_views
  from users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
close_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id_text
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
normalized_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    nullif(trim(coalesce(u.location, '')), '') as location_clean,
    case
      when u.websiteurl ~* '^(https?://)?(www\.)?stackoverflow\.com' then 'StackOverflow'
      when u.websiteurl is null then 'None'
      when u.websiteurl = '' then 'None'
      else 'External'
    end as website_type
  from users u
),
accepted_answer_delta as (
  select
    q.id as question_id,
    q.acceptedanswerid,
    a.owneruserid as answer_userid,
    a.score as accepted_score,
    a.creationdate as accepted_date,
    q.creationdate as question_date,
    extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
    and q.acceptedanswerid is not null
),
user_quality as (
  select
    u.id as userid,
    avg(case when q.posttypeid = 1 then q.score end) as avg_q_score,
    avg(case when a.posttypeid = 2 then a.score end) as avg_a_score,
    sum(case when a.posttypeid = 2 and a.score > 0 then 1 else 0 end) as pos_answers,
    sum(case when a.posttypeid = 2 and a.score < 0 then 1 else 0 end) as neg_answers
  from users u
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  group by u.id
),
post_score_trend as (
  select
    p.id as postid,
    p.owneruserid,
    p.posttypeid,
    p.creationdate,
    p.score,
    avg(p.score) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as mov_avg_score_11,
    sum(p.score) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_score_by_user
  from posts p
),
post_anomalies as (
  select
    pst.postid,
    pst.owneruserid,
    case
      when pst.score > coalesce(pst.mov_avg_score_11, 0) * 3 and pst.score >= 10 then 1
      else 0
    end as high_outlier,
    case
      when pst.score < coalesce(pst.mov_avg_score_11, 0) / 3 and pst.score <= -3 then 1
      else 0
    end as low_outlier
  from post_score_trend pst
),
user_rank as (
  select
    u.id as userid,
    dense_rank() over (order by u.reputation desc, u.id) as rep_rank_global,
    ntile(10) over (order by u.reputation) as rep_decile
  from users u
),
dup_network as (
  select
    pl.postid as dup_postid,
    pl.relatedpostid as original_postid,
    count(*) over (partition by pl.relatedpostid) as original_dup_incoming
  from postlinks pl
  where pl.linktypeid = 3
),
final_posts as (
  select
    rp.id,
    rp.posttypeid,
    rp.owneruserid,
    rp.creationdate,
    rp.score,
    rp.viewcount,
    rp.title,
    rp.tags,
    rp.answercount,
    rp.closeddate,
    rp.rn_owner,
    rp.rn_type,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.total_votes,0) as total_votes,
    coalesce(va.bounty_started,0) as bounty_started,
    coalesce(va.bounty_awarded,0) as bounty_awarded,
    va.first_vote_at,
    va.last_vote_at,
    coalesce(ca.comment_count,0) as comment_count,
    ca.pos_comment_count,
    ca.avg_nonzero_comment_score,
    ca.last_comment_at,
    coalesce(pla.linked_count,0) as linked_count,
    coalesce(pla.duplicate_count,0) as duplicate_count,
    pla.last_link_at,
    ce.close_events,
    ce.reopen_events,
    ce.last_closed_at,
    ce.last_reopened_at,
    ce.last_close_reason_id_text,
    an.high_outlier,
    an.low_outlier,
    dn.original_postid as dup_original_postid,
    dn.original_dup_incoming
  from recent_posts rp
  left join vote_agg va on va.postid = rp.id
  left join comment_agg ca on ca.postid = rp.id
  left join postlink_agg pla on pla.postid = rp.id
  left join close_events ce on ce.postid = rp.id
  left join post_anomalies an on an.postid = rp.id
  left join dup_network dn on dn.dup_postid = rp.id
),
owner_enriched as (
  select
    fp.*,
    nu.displayname,
    nu.reputation,
    nu.creationdate as user_creationdate,
    nu.lastaccessdate as user_lastaccess,
    nu.location_clean,
    nu.website_type,
    oa.q_count,
    oa.a_count,
    oa.avg_nonzero_score as user_avg_nonzero_post_score,
    oa.median_score as user_median_post_score,
    oa.last_activity as user_last_post_activity,
    oa.total_views as user_total_post_views,
    ubs.total_badges,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges,
    ubs.last_badge_date,
    uq.avg_q_score,
    uq.avg_a_score,
    uq.pos_answers,
    uq.neg_answers,
    ur.rep_rank_global,
    ur.rep_decile
  from final_posts fp
  left join normalized_users nu on nu.id = fp.owneruserid
  left join owner_activity oa on oa.userid = fp.owneruserid
  left join user_badge_summary ubs on ubs.userid = fp.owneruserid
  left join user_quality uq on uq.userid = fp.owneruserid
  left join user_rank ur on ur.userid = fp.owneruserid
),
tagged_top as (
  select
    tr.postid,
    string_agg(tr.tagname, ',' order by tr.tag_rank_in_post) filter (where tr.tag_rank_in_post <= 3) as top3_tags,
    max(tr.tag_global_usage) filter (where tr.tag_rank_in_post = 1) as top_tag_global_usage
  from tag_rank tr
  group by tr.postid
),
post_quality_score as (
  select
    oe.id as postid,
    (
      0.5 * coalesce(oe.score,0) +
      0.3 * coalesce(oe.upvotes - oe.downvotes,0) +
      0.1 * ln(1 + greatest(coalesce(oe.viewcount,0),0)) +
      0.2 * coalesce(oe.comment_count,0) +
      case when oe.duplicate_count > 0 then -2 else 0 end +
      case when oe.close_events > 0 then -1 else 0 end +
      case when oe.high_outlier = 1 then 1.5 else 0 end -
      case when oe.low_outlier = 1 then 1.0 else 0 end
    )::numeric(18,4) as quality_score
  from owner_enriched oe
),
correlated_penalties as (
  select
    oe.id as postid,
    (
      select count(*)
      from posts p2
      where p2.owneruserid = oe.owneruserid
        and p2.posttypeid = oe.posttypeid
        and p2.creationdate between oe.creationdate - interval '30 days' and oe.creationdate
        and p2.id <> oe.id
    ) as recent_same_type_by_owner_30d,
    (
      select avg(score)
      from posts p3
      where p3.owneruserid = oe.owneruserid
        and p3.creationdate < oe.creationdate
    ) as owner_prev_avg_score
  from owner_enriched oe
),
ranked as (
  select
    oe.*,
    tt.top3_tags,
    tt.top_tag_global_usage,
    pqs.quality_score,
    cp.recent_same_type_by_owner_30d,
    cp.owner_prev_avg_score,
    rank() over (partition by oe.posttypeid order by pqs.quality_score desc nulls last, oe.score desc, oe.viewcount desc, oe.id) as qual_rank_within_type,
    dense_rank() over (order by pqs.quality_score desc nulls last) as qual_rank_global
  from owner_enriched oe
  left join tagged_top tt on tt.postid = oe.id
  left join post_quality_score pqs on pqs.postid = oe.id
  left join correlated_penalties cp on cp.postid = oe.id
)
select
  r.id as post_id,
  r.posttypeid,
  coalesce(r.title, concat('[post #', r.id::text, ']')) as post_title_fallback,
  r.owneruserid,
  coalesce(r.displayname, '(anonymous)') as owner_displayname,
  r.reputation,
  r.rep_rank_global,
  r.rep_decile,
  r.creationdate as post_created_at,
  r.user_creationdate as user_created_at,
  r.score,
  r.viewcount,
  r.upvotes,
  r.downvotes,
  r.total_votes,
  r.comment_count,
  r.linked_count,
  r.duplicate_count,
  r.close_events,
  r.reopen_events,
  r.high_outlier,
  r.low_outlier,
  r.quality_score,
  r.qual_rank_within_type,
  r.qual_rank_global,
  r.top3_tags,
  r.top_tag_global_usage,
  r.rn_owner as recency_rank_for_owner,
  r.rn_type as score_rank_for_type,
  r.bounty_started,
  r.bounty_awarded,
  r.first_vote_at,
  r.last_vote_at,
  r.last_comment_at,
  r.last_link_at,
  r.last_closed_at,
  r.last_reopened_at,
  r.last_close_reason_id_text,
  r.location_clean,
  r.website_type,
  r.q_count,
  r.a_count,
  r.user_avg_nonzero_post_score,
  r.user_median_post_score,
  r.user_last_post_activity,
  r.user_total_post_views,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.last_badge_date,
  r.avg_q_score,
  r.avg_a_score,
  r.pos_answers,
  r.neg_answers,
  r.dup_original_postid,
  r.original_dup_incoming,
  r.recent_same_type_by_owner_30d,
  r.owner_prev_avg_score,
  aa.hours_to_accept as accepted_hours_to_accept,
  aa.accepted_score as accepted_answer_score
from ranked r
left join accepted_answer_delta aa on aa.question_id = r.id
where (r.posttypeid in (1,2) or r.quality_score is not null)
  and coalesce(r.viewcount,0) >= 0
  and (r.closeddate is null or r.reopen_events is not null or r.duplicate_count = 0)
  and (r.top3_tags is null or position('sql' in lower(r.top3_tags)) = 0 or r.score >= 0)
order by
  r.qual_rank_global nulls last,
  r.qual_rank_within_type nulls last,
  r.id
limit 500;