-- {"query": "70.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3246} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    extract(year from u.creationdate) as join_year,
    row_number() over (order by u.reputation desc, u.id) as rn_toprep
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
active_posts as (
  select
    p.id,
    p.posttypeid,
    p.title,
    p.tags,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.closeddate
  from posts p
  where p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from posts)
),
user_activity as (
  select
    u.user_id,
    count(*) filter (where ap.posttypeid = 1) as q_count,
    count(*) filter (where ap.posttypeid = 2) as a_count,
    sum(coalesce(ap.score,0)) as post_score_sum,
    max(ap.lastactivitydate) as last_post_activity
  from recent_users u
  left join active_posts ap
    on ap.owneruserid = u.user_id
  group by u.user_id
),
votes_agg as (
  select
    u.user_id,
    sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes_cast,
    sum(case when vt.name = 'DownMod' = true then 1 else 0 end) as downvotes_cast,
    count(*) filter (where vt.name in ('Favorite')) as favorites_cast,
    sum(case when vt.name = 'BountyStart' then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when vt.name = 'BountyClose' then coalesce(v.bountyamount,0) else 0 end) as bounty_earned
  from recent_users u
  left join votes v
    on v.userid = u.user_id
  left join votetypes vt
    on vt.id = v.votetypeid
  group by u.user_id
),
comments_agg as (
  select
    u.user_id,
    count(c.id) as comment_count,
    sum(coalesce(c.score,0)) as comment_score_sum,
    max(c.creationdate) as last_comment_date
  from recent_users u
  left join comments c
    on c.userid = u.user_id
  group by u.user_id
),
badges_agg as (
  select
    u.user_id,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    count(*) filter (where b.tagbased = 1) as tag_badges,
    max(b.date) as last_badge_date
  from recent_users u
  left join badges b
    on b.userid = u.user_id
  group by u.user_id
),
question_quality as (
  select
    q.owneruserid as user_id,
    count(q.id) as questions_total,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_q,
    avg(nullif(q.viewcount,0)) as avg_q_views,
    percentile_cont(0.5) within group (order by coalesce(q.score,0)) as median_q_score
  from posts q
  where q.posttypeid = 1
    and q.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from posts)
  group by q.owneruserid
),
answer_quality as (
  select
    a.owneruserid as user_id,
    count(a.id) as answers_total,
    sum(case when exists (
      select 1
      from posts q
      where q.id = a.parentid
        and q.acceptedanswerid = a.id
    ) then 1 else 0 end) as accepted_as,
    avg(coalesce(a.score,0)) as avg_a_score,
    percentile_cont(0.5) within group (order by coalesce(a.score,0)) as median_a_score
  from posts a
  where a.posttypeid = 2
    and a.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from posts)
  group by a.owneruserid
),
tag_influence as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname,
    count(*) as posts_in_tag,
    sum(coalesce(p.score,0)) as score_in_tag
  from posts p
  where p.posttypeid in (1,2)
    and p.tags is not null
    and p.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from posts)
  group by p.owneruserid, unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))
),
top_tag_per_user as (
  select distinct on (ti.user_id)
    ti.user_id,
    ti.tagname,
    ti.posts_in_tag,
    ti.score_in_tag
  from tag_influence ti
  order by ti.user_id, ti.score_in_tag desc, ti.posts_in_tag desc, ti.tagname
),
postlinks_agg as (
  select
    u.user_id,
    count(pl.id) filter (where lt.name = 'Duplicate') as dup_links,
    count(pl.id) filter (where lt.name = 'Linked') as linked_links
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join postlinks pl on pl.postid = p.id
  left join linktypes lt on lt.id = pl.linktypeid
  group by u.user_id
),
close_events as (
  select
    ph.postid,
    ph.creationdate as closed_at,
    ph.userid as closer_userid,
    cast(nullif(ph.comment,'') as int) as closereasonid
  from posthistory ph
  where ph.posthistorytypeid = 10
),
close_reasons as (
  select
    ce.postid,
    crt.name as close_reason_name,
    ce.closed_at
  from close_events ce
  left join closereasontypes crt
    on crt.id = ce.closereasonid
),
user_close_stats as (
  select
    u.user_id,
    count(distinct case when p.posttypeid = 1 then p.id end) filter (where cr.close_reason_name is not null) as questions_closed,
    count(*) filter (where cr.close_reason_name = 'Duplicate') as closed_as_duplicate
  from recent_users u
  left join posts p on p.owneruserid = u.user_id
  left join close_reasons cr on cr.postid = p.id
  group by u.user_id
),
engagement_rank as (
  select
    u.user_id,
    dense_rank() over (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0) desc, coalesce(ua.post_score_sum,0) desc) as activity_rank,
    dense_rank() over (order by coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0) desc) as net_votes_rank,
    dense_rank() over (order by coalesce(ba.badge_count,0) desc, coalesce(ba.gold_count,0) desc) as badge_rank
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join votes_agg va on va.user_id = u.user_id
  left join badges_agg ba on ba.user_id = u.user_id
),
normalized as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.join_year,
    ua.q_count,
    ua.a_count,
    ua.post_score_sum,
    coalesce(va.upvotes_cast,0) as upvotes_cast,
    coalesce(va.downvotes_cast,0) as downvotes_cast,
    coalesce(va.favorites_cast,0) as favorites_cast,
    coalesce(va.bounty_started,0) as bounty_started,
    coalesce(va.bounty_earned,0) as bounty_earned,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(ca.comment_score_sum,0) as comment_score_sum,
    coalesce(ba.badge_count,0) as badge_count,
    coalesce(ba.gold_count,0) as gold_count,
    coalesce(ba.silver_count,0) as silver_count,
    coalesce(ba.bronze_count,0) as bronze_count,
    coalesce(ba.tag_badges,0) as tag_badges,
    qq.questions_total,
    qq.accepted_q,
    qq.avg_q_views,
    qq.median_q_score,
    aq.answers_total,
    aq.accepted_as,
    aq.avg_a_score,
    aq.median_a_score,
    ttp.tagname as top_tag,
    ttp.posts_in_tag as top_tag_posts,
    ttp.score_in_tag as top_tag_score,
    pa.dup_links,
    pa.linked_links,
    uas.questions_closed,
    uas.closed_as_duplicate,
    er.activity_rank,
    er.net_votes_rank,
    er.badge_rank
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join votes_agg va on va.user_id = u.user_id
  left join comments_agg ca on ca.user_id = u.user_id
  left join badges_agg ba on ba.user_id = u.user_id
  left join question_quality qq on qq.user_id = u.user_id
  left join answer_quality aq on aq.user_id = u.user_id
  left join top_tag_per_user ttp on ttp.user_id = u.user_id
  left join postlinks_agg pa on pa.user_id = u.user_id
  left join user_close_stats uas on uas.user_id = u.user_id
  left join engagement_rank er on er.user_id = u.user_id
),
score_calc as (
  select
    n.*,
    -- composite score emphasizing balanced activity, normalized by simple heuristics
    (
      0.30 * ln(1 + coalesce(n.q_count,0) + coalesce(n.a_count,0)) +
      0.25 * ln(1 + greatest(coalesce(n.post_score_sum,0),0)) +
      0.15 * ln(1 + coalesce(n.badge_count,0) + 2*coalesce(n.gold_count,0)) +
      0.10 * ln(1 + coalesce(n.comment_count,0) + greatest(coalesce(n.comment_score_sum,0),0)) +
      0.10 * ln(1 + coalesce(n.upvotes_cast,0) - least(coalesce(n.downvotes_cast,0),0)) +
      0.05 * ln(1 + coalesce(n.bounty_earned,0)) +
      0.05 * ln(1 + coalesce(n.top_tag_score,0))
    ) as engagement_score,
    case
      when n.websiteurl ilike '%github%' or n.websiteurl ilike '%gitlab%' then 1
      when n.location ilike '%stack overflow%' then 1
      else 0
    end as ext_signal
  from normalized n
),
ranked as (
  select
    s.*,
    row_number() over (
      order by s.engagement_score desc,
               s.reputation desc,
               coalesce(s.accepted_as,0) + coalesce(s.accepted_q,0) desc,
               s.activity_rank,
               s.user_id
    ) as overall_rank
  from score_calc s
),
null_logic_check as (
  select
    r.*,
    case
      when r.top_tag is null and (coalesce(r.q_count,0) + coalesce(r.a_count,0)) > 0 then 'untagged-or-missing'
      when r.top_tag is null then 'no-activity'
      else lower(r.top_tag)
    end as normalized_top_tag,
    coalesce(r.avg_q_views, 0) as nz_avg_q_views,
    coalesce(r.median_q_score, 0) as nz_median_q_score,
    coalesce(r.avg_a_score, 0) as nz_avg_a_score,
    coalesce(r.median_a_score, 0) as nz_median_a_score
  from ranked r
)
select
  nl.overall_rank,
  nl.user_id,
  nl.displayname,
  nl.reputation,
  nl.join_year,
  nl.q_count,
  nl.a_count,
  nl.questions_total,
  nl.answers_total,
  nl.accepted_q,
  nl.accepted_as,
  nl.engagement_score,
  nl.activity_rank,
  nl.net_votes_rank,
  nl.badge_rank,
  nl.badge_count,
  nl.gold_count,
  nl.silver_count,
  nl.bronze_count,
  nl.upvotes_cast,
  nl.downvotes_cast,
  nl.favorites_cast,
  nl.bounty_started,
  nl.bounty_earned,
  nl.comment_count,
  nl.comment_score_sum,
  nl.top_tag as top_tag_raw,
  nl.normalized_top_tag as top_tag,
  nl.top_tag_posts,
  nl.top_tag_score,
  nl.dup_links,
  nl.linked_links,
  nl.questions_closed,
  nl.closed_as_duplicate,
  nl.nz_avg_q_views as avg_q_views,
  nl.nz_median_q_score as median_q_score,
  nl.nz_avg_a_score as avg_a_score,
  nl.nz_median_a_score as median_a_score,
  nl.ext_signal,
  case when nl.closed_as_duplicate > 0 or nl.dup_links > 0 then 'DUP-PRONE' else 'OK' end as dup_flag,
  case when nl.reputation >= (select percentile_cont(0.9) within group (order by reputation) from users) then 'P90+' else 'P<90' end as rep_bucket
from null_logic_check nl
where
  (
    nl.rn_toprep <= 200
    or nl.engagement_score >= (
      select percentile_cont(0.95) within group (order by engagement_score)
      from score_calc
    )
  )
  and (
    nl.last_post_activity is null
    or nl.last_post_activity >= nl.creationdate
    or nl.last_post_activity >= nl.lastaccessdate - interval '180 days'
  )
order by nl.overall_rank
limit 200;