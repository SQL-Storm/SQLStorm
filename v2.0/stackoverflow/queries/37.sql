-- {"query": "37.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3131}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(case when p.posttypeid = 1 then 1 end) as q_count,
    count(case when p.posttypeid = 2 then 1 end) as a_count,
    avg(case when p.posttypeid in (1,2) then nullif(p.score,0) end) as avg_nonzero_score,
    sum(coalesce(p.viewcount,0)) as total_views,
    max(p.lastactivitydate) as last_activity
  from posts p
  group by p.owneruserid
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(case when b.class = 1 then 1 end) as gold_badges,
    count(case when b.class = 2 then 1 end) as silver_badges,
    count(case when b.class = 3 then 1 end) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
votes_rollup as (
  select
    p.owneruserid as user_id,
    count(case when v.votetypeid = 2 then 1 end) as upvotes_received,
    count(case when v.votetypeid = 3 then 1 end) as downvotes_received,
    sum(case when v.votetypeid in (8,9) then v.bountyamount else 0 end) as bounty_total
  from posts p
  left join votes v on v.postid = p.id
  group by p.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_date,
    sum(case when lower(c.text) like '%thanks%' then 1 else 0 end) as thanks_count
  from comments c
  group by c.userid
),
question_tag_expansion as (
  select
    p.id as question_id,
    p.owneruserid as user_id,
    unnest(
      case
        when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
        then string_to_array(substring(p.tags from 2 for length(p.tags)-2), '><')
        else array[]::varchar[]  -- keep array literal; some dialects may ignore but it's safe here
      end
    ) as tagname
  from posts p
  where p.posttypeid = 1
),
top_tags_per_user as (
  select
    q.user_id,
    q.tagname,
    count(*) as tag_uses,
    row_number() over (partition by q.user_id order by count(*) desc, q.tagname) as rn
  from question_tag_expansion q
  group by q.user_id, q.tagname
),
accepted_answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers,
    avg(a.score) as avg_score_on_accepted
  from posts q
  join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
  where q.posttypeid = 1
  group by a.owneruserid
),
closed_questions as (
  select
    q.owneruserid as user_id,
    count(*) as closed_q,
    count(case when q.closeddate is not null and q.score < 0 then 1 end) as closed_neg_q
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
merge_dupe_graph as (
  select
    pl.postid as post_id,
    pl.relatedpostid as related_post_id,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid in (1,3)
),
user_link_metrics as (
  select
    p.owneruserid as user_id,
    count(distinct case when mg.linktypeid = 3 then mg.related_post_id end) as dupe_links_out,
    count(distinct case when mg.linktypeid = 1 then mg.related_post_id end) as links_out
  from posts p
  left join merge_dupe_graph mg on mg.post_id = p.id
  group by p.owneruserid
),
post_edits as (
  select
    ph.postid,
    ph.userid as editor_user_id,
    count(case when ph.posthistorytypeid in (4,5,6) then 1 end) as edit_actions,
    min(ph.creationdate) as first_edit,
    max(ph.creationdate) as last_edit
  from posthistory ph
  group by ph.postid, ph.userid
),
self_edit_activity as (
  select
    p.owneruserid as user_id,
    sum(pe.edit_actions) as self_edits,
    max(pe.last_edit) as last_self_edit
  from post_edits pe
  join posts p on p.id = pe.postid and p.owneruserid = pe.editor_user_id
  group by p.owneruserid
),
cross_edit_activity as (
  select
    pe.editor_user_id as user_id,
    sum(pe.edit_actions) as edits_on_others,
    max(pe.last_edit) as last_cross_edit
  from post_edits pe
  join posts p on p.id = pe.postid and (p.owneruserid is distinct from pe.editor_user_id)
  group by pe.editor_user_id
),
recent_hot_bumps as (
  select
    ph.postid,
    ph.userid as user_id,
    count(case when ph.posthistorytypeid in (50,52) then 1 end) as bumps_or_hot
  from posthistory ph
  where ph.creationdate >= (select max(creationdate) - interval '180 days' from posthistory)
  group by ph.postid, ph.userid
),
user_null_sentinels as (
  select
    u.id as user_id,
    case when u.displayname is null or trim(u.displayname) = '' then 1 else 0 end as is_anonish,
    case when u.location is null or trim(u.location) = '' then 1 else 0 end as is_loc_missing
  from users u
),
cohorts as (
  select
    ru.user_id,
    ru.cohort_month,
    row_number() over (partition by ru.cohort_month order by ru.reputation desc, ru.user_id) as rank_in_cohort
  from recent_users ru
),
agg as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ua.q_count,
    ua.a_count,
    ua.avg_nonzero_score,
    ua.total_views,
    ua.last_activity,
    br.total_badges,
    br.gold_badges,
    br.silver_badges,
    br.bronze_badges,
    br.last_badge_date,
    vr.upvotes_received,
    vr.downvotes_received,
    coalesce(vr.bounty_total,0) as bounty_total,
    cs.comment_count,
    cs.avg_comment_score,
    cs.last_comment_date,
    cs.thanks_count,
    aam.accepted_answers,
    aam.avg_score_on_accepted,
    cq.closed_q,
    cq.closed_neg_q,
    ulm.dupe_links_out,
    ulm.links_out,
    sea.self_edits,
    sea.last_self_edit,
    cea.edits_on_others,
    cea.last_cross_edit,
    rhb.bumps_or_hot,
    uns.is_anonish,
    uns.is_loc_missing,
    ch.rank_in_cohort,
    ru.creationdate
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join badge_rollup br on br.user_id = ru.user_id
  left join votes_rollup vr on vr.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join accepted_answer_metrics aam on aam.user_id = ru.user_id
  left join closed_questions cq on cq.user_id = ru.user_id
  left join user_link_metrics ulm on ulm.user_id = ru.user_id
  left join self_edit_activity sea on sea.user_id = ru.user_id
  left join cross_edit_activity cea on cea.user_id = ru.user_id
  left join recent_hot_bumps rhb on rhb.user_id = ru.user_id
  left join user_null_sentinels uns on uns.user_id = ru.user_id
  left join cohorts ch on ch.user_id = ru.user_id
),
score_calc as (
  select
    a.*,
    (
      coalesce(ln(nullif(a.q_count,0)+1),0) * 0.8 +
      coalesce(ln(nullif(a.a_count,0)+1),0) * 1.2 +
      coalesce(ln(nullif(a.total_views,0)+1),0) * 0.3 +
      coalesce(a.avg_nonzero_score,0) * 0.5 +
      coalesce(a.upvotes_received,0) * 0.2 -
      coalesce(a.downvotes_received,0) * 0.4 +
      coalesce(a.accepted_answers,0) * 2.0 +
      coalesce(a.gold_badges,0) * 3.0 +
      coalesce(a.silver_badges,0) * 1.5 +
      coalesce(a.bronze_badges,0) * 0.5 +
      coalesce(ln(nullif(a.edits_on_others,0)+1),0) * 0.7 +
      coalesce(ln(nullif(a.self_edits,0)+1),0) * 0.4 +
      case when a.is_anonish = 1 then -1.0 else 0.0 end +
      case when a.is_loc_missing = 1 then -0.3 else 0.0 end +
      least(coalesce(a.bounty_total,0) / 50.0, 10.0)
    ) as activity_score
  from agg a
),
top_tag_pivot as (
  select
    t.user_id,
    max(case when t.rn = 1 then t.tagname end) as top_tag_1,
    max(case when t.rn = 2 then t.tagname end) as top_tag_2,
    max(case when t.rn = 3 then t.tagname end) as top_tag_3
  from top_tags_per_user t
  where t.rn <= 3
  group by t.user_id
),
question_answer_ratio as (
  select
    a.user_id,
    case
      when coalesce(a.a_count,0) = 0 and coalesce(a.q_count,0) = 0 then null
      when coalesce(a.a_count,0) = 0 then 0.0
      else round(cast(coalesce(a.q_count,0) as numeric) / nullif(a.a_count,0), 4)
    end as q_to_a_ratio
  from agg a
),
ranked as (
  select
    sc.user_id,
    sc.displayname,
    sc.reputation,
    sc.cohort_month,
    sc.q_count,
    sc.a_count,
    sc.avg_nonzero_score,
    sc.total_views,
    sc.last_activity,
    sc.total_badges,
    sc.gold_badges,
    sc.silver_badges,
    sc.bronze_badges,
    sc.last_badge_date,
    sc.upvotes_received,
    sc.downvotes_received,
    sc.bounty_total,
    sc.comment_count,
    sc.avg_comment_score,
    sc.last_comment_date,
    sc.thanks_count,
    sc.accepted_answers,
    sc.avg_score_on_accepted,
    sc.closed_q,
    sc.closed_neg_q,
    sc.dupe_links_out,
    sc.links_out,
    sc.self_edits,
    sc.last_self_edit,
    sc.edits_on_others,
    sc.last_cross_edit,
    sc.bumps_or_hot,
    sc.is_anonish,
    sc.is_loc_missing,
    sc.rank_in_cohort,
    sc.activity_score,
    sc.creationdate,
    ttp.top_tag_1,
    ttp.top_tag_2,
    ttp.top_tag_3,
    qar.q_to_a_ratio,
    row_number() over (
      order by sc.activity_score desc nulls last,
               sc.reputation desc,
               coalesce(sc.last_activity, sc.creationdate) desc,
               sc.user_id
    ) as global_rank,
    dense_rank() over (
      partition by sc.cohort_month
      order by sc.activity_score desc nulls last, sc.reputation desc
    ) as cohort_rank
  from score_calc sc
  left join top_tag_pivot ttp on ttp.user_id = sc.user_id
  left join question_answer_ratio qar on qar.user_id = sc.user_id
),
dupe_suspicions as (
  select
    q.owneruserid as user_id,
    count(case when exists (
        select 1
        from postlinks pl
        where pl.postid = q.id and pl.linktypeid = 3
      ) and q.score <= 0 then 1 end) as suspicious_dupes
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
final as (
  select
    r.user_id,
    r.displayname,
    r.reputation,
    r.cohort_month,
    r.rank_in_cohort,
    r.global_rank,
    r.cohort_rank,
    r.activity_score,
    r.q_count,
    r.a_count,
    r.q_to_a_ratio,
    r.total_views,
    r.upvotes_received,
    r.downvotes_received,
    r.accepted_answers,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.links_out,
    r.dupe_links_out,
    r.edits_on_others,
    r.self_edits,
    r.last_activity,
    r.last_comment_date,
    r.last_badge_date,
    r.last_self_edit,
    r.last_cross_edit,
    coalesce(ttp.top_tag_1, 'unknown') as top_tag_1,
    coalesce(ttp.top_tag_2, 'unknown') as top_tag_2,
    coalesce(ttp.top_tag_3, 'unknown') as top_tag_3,
    coalesce(ds.suspicious_dupes,0) as suspicious_dupes,
    r.creationdate
  from ranked r
  left join top_tag_pivot ttp on ttp.user_id = r.user_id
  left join dupe_suspicions ds on ds.user_id = r.user_id
)
select *
from final
where
  (displayname is not null and length(trim(displayname)) >= 3)
  and (coalesce(top_tag_1, '') <> coalesce(top_tag_2, '') or top_tag_2 is null)
  and not (coalesce(q_count,0) = 0 and coalesce(a_count,0) = 0)
  and (
    coalesce(last_activity, timestamp '1970-01-01 00:00:00') >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    or cohort_rank <= 10
    or activity_score >= (
      select percentile_cont(0.95) within group (order by activity_score)
      from ranked
    )
  )
order by global_rank
limit 200;