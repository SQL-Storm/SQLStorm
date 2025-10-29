with
recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)),''), 'Unknown') as region_hint,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
   and b.date >= u.creationdate
  where u.reputation >= (
    select percentile_disc(0.75) within group (order by reputation) from users
  )
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, region_hint
),
recent_questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.title,
    p.score,
    p.viewcount,
    p.answercount,
    p.closeddate,
    p.communityowneddate,
    p.tags,
    array_length(string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><'), 1) as tag_count,
    string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
),
question_tags as (
  select
    rq.id as question_id,
    lower(t) as tag_name
  from recent_questions rq,
  unnest(rq.tag_arr) as t
),
tag_stats as (
  select
    qt.tag_name,
    count(*) as question_count,
    sum(rq.viewcount) as total_views,
    sum(case when rq.score > 0 then rq.score else 0 end) as nonneg_score,
    avg(rq.viewcount) as avg_views,
    dense_rank() over (order by count(*) desc, sum(rq.viewcount) desc) as pop_rank
  from question_tags qt
  join recent_questions rq on rq.id = qt.question_id
  group by qt.tag_name
),
user_q_agg as (
  select
    rq.owneruserid as userid,
    count(*) as q_count,
    sum(coalesce(rq.viewcount,0)) as q_views,
    sum(coalesce(rq.score,0)) as q_score,
    avg(coalesce(rq.viewcount,0)) as avg_q_views,
    max(rq.creationdate) as last_q_date
  from recent_questions rq
  where rq.owneruserid is not null
  group by rq.owneruserid
),
recent_answers as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as userid,
    p.creationdate,
    p.score,
    lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_ans_time,
    lead(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as next_ans_time
  from posts p
  where p.posttypeid = 2
    and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
),
user_a_agg as (
  select
    ra.userid,
    count(*) as a_count,
    sum(coalesce(ra.score,0)) as a_score,
    avg(extract(epoch from (ra.creationdate - ra.prev_ans_time)) / 3600.0) filter (where ra.prev_ans_time is not null) as avg_hours_between_answers,
    max(ra.creationdate) as last_a_date
  from recent_answers ra
  where ra.userid is not null
  group by ra.userid
),
user_votes as (
  select
    p.owneruserid as userid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcv,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcv,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounties_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounties_awarded
  from votes v
  join posts p on p.id = v.postid
  where v.creationdate >= (select max(creationdate) - interval '730 days' from votes)
    and p.owneruserid is not null
  group by p.owneruserid
),
user_comments as (
  select
    coalesce(c.userid, -1) as userid,
    count(*) as c_count,
    sum(c.score) as c_score,
    max(c.creationdate) as last_c_date
  from comments c
  where c.creationdate >= (select max(creationdate) - interval '730 days' from comments)
  group by coalesce(c.userid, -1)
),
user_link_rel as (
  select
    p.owneruserid as userid,
    count(case when pl.linktypeid = 3 then 1 end) as dup_links,
    count(case when pl.linktypeid = 1 then 1 end) as linked_links,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dups_to,
    count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as distinct_links_to
  from postlinks pl
  join posts p on p.id = pl.postid
  where p.owneruserid is not null
    and pl.creationdate >= (select max(creationdate) - interval '730 days' from postlinks)
  group by p.owneruserid
),
user_closures as (
  select
    p.owneruserid as userid,
    count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
    count(case when ph.posthistorytypeid = 11 then 1 end) as reopen_events,
    count(case when (ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$' and (ph.comment ~~ '[0-9]%')) then case when cast(ph.comment as integer) in (101,102,103,104,105) then 1 end end) as modern_closes
  from posthistory ph
  join posts p on p.id = ph.postid and p.posttypeid = 1
  where ph.creationdate >= (select max(creationdate) - interval '730 days' from posthistory)
    and p.owneruserid is not null
  group by p.owneruserid
),
user_activity as (
  select
    ru.id as userid,
    ru.displayname,
    ru.reputation,
    ru.region_hint,
    coalesce(uq.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(uq.q_views,0) + coalesce(uq.q_score,0)*50 + coalesce(ua.a_score,0)*30 + coalesce(uv.upvotes_rcv,0)*10 - coalesce(uv.downvotes_rcv,0)*20 + coalesce(uv.bounties_awarded,0) as engagement_score,
    (extract(epoch from (greatest(coalesce(uq.last_q_date, ru.creationdate), coalesce(ua.last_a_date, ru.creationdate), coalesce(uc.last_c_date, ru.creationdate)) - ru.creationdate)) / 86400.0) as active_days,
    coalesce(uc.c_count,0) as c_count,
    coalesce(ul.dup_links,0) as dup_links,
    coalesce(ul.linked_links,0) as linked_links,
    coalesce(uc.c_score,0) as c_score,
    coalesce(uq.avg_q_views,0) as avg_q_views,
    coalesce(ua.avg_hours_between_answers,0) as avg_hours_between_answers,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    coalesce(uv.upvotes_rcv,0) as upvotes_rcv,
    coalesce(uv.downvotes_rcv,0) as downvotes_rcv,
    coalesce(uv.bounties_started,0) as bounties_started,
    coalesce(uv.bounties_awarded,0) as bounties_awarded,
    coalesce(uc.last_c_date, ru.creationdate) as last_c_date
  from recent_users ru
  left join user_q_agg uq on uq.userid = ru.id
  left join user_a_agg ua on ua.userid = ru.id
  left join user_votes uv on uv.userid = ru.id
  left join user_comments uc on uc.userid = ru.id
  left join user_link_rel ul on ul.userid = ru.id
),
user_top_tags as (
  select
    p.owneruserid as userid,
    qt.tag_name,
    count(*) as uses,
    sum(coalesce(p.score,0)) as tag_score,
    dense_rank() over (partition by p.owneruserid order by count(*) desc, sum(coalesce(p.score,0)) desc, min(p.creationdate)) as tag_rank
  from posts p
  join question_tags qt on qt.question_id = p.id
  where p.posttypeid = 1
    and p.owneruserid is not null
  group by p.owneruserid, qt.tag_name
),
user_tag_impact as (
  select
    utt.userid,
    sum(uses * greatest(ts.nonneg_score,1) * (1.0 / nullif(utt.tag_rank,0))) as weighted_tag_influence,
    max(case when utt.tag_rank = 1 then utt.tag_name end) as top_tag
  from user_top_tags utt
  join tag_stats ts on ts.tag_name = utt.tag_name
  where utt.tag_rank <= 5
  group by utt.userid
),
scored_users as (
  select
    ua.*,
    coalesce(uti.weighted_tag_influence, 0) as weighted_tag_influence,
    uti.top_tag,
    case
      when (ua.q_count + ua.a_count + ua.c_count) = 0 then 'Dormant'
      when ua.engagement_score >= 10000 then 'Elite'
      when ua.engagement_score >= 3000 then 'Active'
      when ua.engagement_score >= 800 then 'Contributor'
      else 'Occasional'
    end as activity_band,
    row_number() over (order by ua.engagement_score desc nulls last, ua.reputation desc) as global_rank,
    percent_rank() over (order by ua.engagement_score) as pr_engagement,
    ntile(20) over (order by ua.engagement_score desc) as vigintile
  from user_activity ua
  left join user_tag_impact uti on uti.userid = ua.userid
),
answer_accepts as (
  select
    a.owneruserid as userid,
    count(case when q.acceptedanswerid = a.id then 1 end) as accepted_answers,
    count(*) as total_answers
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
    and a.creationdate >= (select max(creationdate) - interval '730 days' from posts)
    and a.owneruserid is not null
  group by a.owneruserid
),
user_quality as (
  select
    ua.userid,
    coalesce(cast(ac.accepted_answers as numeric) / nullif(ac.total_answers,0), 0) as accept_rate,
    coalesce(uc.close_events,0) as close_events,
    coalesce(uc.reopen_events,0) as reopen_events,
    coalesce(uc.modern_closes,0) as modern_closes,
    coalesce(ul.dup_links,0) as dup_links,
    coalesce(ul.linked_links,0) as linked_links,
    greatest(0,
      100 * coalesce(cast(ac.accepted_answers as numeric) / nullif(ac.total_answers,0), 0)
      + 0.1 * ua.engagement_score
      + 2 * coalesce(ul.linked_links,0)
      - 5 * coalesce(ul.dup_links,0)
      - 10 * coalesce(uc.close_events,0)
      + 6 * coalesce(uc.reopen_events,0)
    ) as quality_score
  from user_activity ua
  left join answer_accepts ac on ac.userid = ua.userid
  left join user_closures uc on uc.userid = ua.userid
  left join user_link_rel ul on ul.userid = ua.userid
),
finalized as (
  select
    su.userid,
    su.displayname,
    su.reputation,
    su.region_hint,
    su.activity_band,
    su.global_rank,
    su.vigintile,
    su.engagement_score,
    su.weighted_tag_influence,
    su.top_tag,
    su.q_count, su.a_count, su.c_count,
    su.upvotes_rcv, su.downvotes_rcv,
    su.bounties_started, su.bounties_awarded,
    su.avg_q_views,
    su.avg_hours_between_answers,
    uq.accept_rate,
    uq.quality_score,
    trim(both ' ' from concat_ws(
      ' | ',
      nullif(su.displayname, ''),
      case when su.top_tag is not null then 'TopTag:' || su.top_tag end,
      case when su.region_hint is not null and su.region_hint <> 'Unknown' then 'Region:' || su.region_hint end,
      'Band:' || su.activity_band
    )) as descriptor,
    (
      select q.title
      from posts q
      where q.posttypeid = 1
        and q.owneruserid = su.userid
      order by coalesce(q.score,0) * 1000 + coalesce(q.viewcount,0) desc, q.creationdate desc
      limit 1
    ) as hottest_question_title,
    (
      select qt.tag_name
      from question_tags qt
      join posts qp on qp.id = qt.question_id and qp.owneruserid = su.userid
      group by qt.tag_name
      order by count(*) desc, max(qp.creationdate) desc
      limit 1
    ) as most_used_recent_tag
  from scored_users su
  left join user_quality uq on uq.userid = su.userid
  where
    (su.engagement_score > 0 or su.weighted_tag_influence > 0)
    and coalesce(uq.accept_rate, 0) >= 0
    and (
      (su.activity_band in ('Elite','Active') and su.vigintile <= 5)
      or (su.activity_band = 'Contributor' and su.global_rank <= 500)
      or (su.activity_band = 'Occasional' and su.engagement_score >= 1000 and su.weighted_tag_influence >= 10000)
    )
),
ranked as (
  select
    f.*,
    row_number() over (
      partition by f.userid
      order by
        f.quality_score desc nulls last,
        f.engagement_score desc nulls last,
        f.weighted_tag_influence desc nulls last
    ) as rn
  from finalized f
)
select
  r.userid,
  r.displayname,
  r.reputation,
  r.region_hint,
  r.activity_band,
  r.global_rank,
  r.vigintile,
  round(r.engagement_score::numeric, 2) as engagement_score,
  round(r.weighted_tag_influence::numeric, 2) as weighted_tag_influence,
  round(r.quality_score::numeric, 2) as quality_score,
  round(coalesce(r.accept_rate,0)::numeric, 4) as accept_rate,
  r.q_count, r.a_count, r.c_count,
  r.upvotes_rcv, r.downvotes_rcv,
  r.bounties_started, r.bounties_awarded,
  round(coalesce(r.avg_q_views,0)::numeric, 2) as avg_q_views,
  round(coalesce(r.avg_hours_between_answers,0)::numeric, 2) as avg_hours_between_answers,
  r.top_tag,
  r.descriptor,
  r.hottest_question_title,
  r.most_used_recent_tag
from ranked r
where r.rn = 1
order by r.quality_score desc nulls last, r.engagement_score desc nulls last, r.userid
limit 500;