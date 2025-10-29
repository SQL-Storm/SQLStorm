with recent_questions as (
  select
    p.id as question_id,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    coalesce(p.answercount, 0) as answercount
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
tag_splits as (
  select
    rq.question_id,
    unnest(string_to_array(substring(rq.tags, 2, length(rq.tags)-2), '><')) as tag
  from recent_questions rq
  where rq.tags is not null
),
tag_quality as (
  select
    ts.tag,
    count(distinct ts.question_id) as q_count,
    avg(cast(rq.score as numeric)) as avg_q_score,
    percentile_cont(0.9) within group (order by rq.viewcount) as p90_views,
    sum(case when rq.answercount >= 1 then 1 else 0 end) as answered_qs
  from tag_splits ts
  join recent_questions rq on rq.question_id = ts.question_id
  group by ts.tag
),
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    date_trunc('month', u.creationdate) as cohort_month,
    coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0) as net_votes_cast,
    coalesce(sum(case when b.class = 1 then 5 when b.class = 2 then 2 when b.class = 3 then 1 else 0 end),0) as badge_weight,
    count(distinct p.id) filter (where p.posttypeid in (1,2)) as posts_authored
  from users u
  left join votes v on v.userid = u.id and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  left join badges b on b.userid = u.id and b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  left join posts p on p.owneruserid = u.id and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by u.id, u.displayname, u.reputation, date_trunc('month', u.creationdate)
),
qa_pairs as (
  select
    q.id as question_id,
    a.id as answer_id,
    a.owneruserid as answerer_id,
    a.score as answer_score,
    a.creationdate as answer_date,
    q.acceptedanswerid,
    case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
  from posts q
  join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
    and q.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answerer_perf as (
  select
    ap.answerer_id,
    count(*) as answers_given,
    sum(case when ap.is_accepted = 1 then 1 else 0 end) as accepted_answers,
    avg(cast(ap.answer_score as numeric)) as avg_answer_score,
    cast(sum(case when ap.answer_score > 0 then 1 else 0 end) as numeric) / nullif(count(*),0) as pos_ratio
  from qa_pairs ap
  group by ap.answerer_id
),
post_link_graph as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    lt.name as link_type
  from postlinks pl
  left join linktypes lt on lt.id = pl.linktypeid
  where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
),
dup_clusters as (
  select
    g.relatedpostid as canonical_id,
    count(*) filter (where g.linktypeid = 3) as dup_inbound,
    count(*) filter (where g.linktypeid = 1) as linked_inbound
  from post_link_graph g
  group by g.relatedpostid
),
edit_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits,
    count(*) filter (where ph.posthistorytypeid in (10)) as closes,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_date,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as first_close_date,
    sum(case when ph.posthistorytypeid = 10 and (ph.comment ~ '^[0-9]+$') then 1 else 0 end) as close_with_reason
  from posthistory ph
  where ph.creationdate >= (select max(creationdate) - interval '365 days' from posthistory)
  group by ph.postid
),
votes_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 9 then v.bountyamount else 0 end) as bounty_awarded,
    count(*) as total_votes,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.postid
),
question_metrics as (
  select
    rq.question_id,
    rq.creationdate,
    rq.title,
    rq.tags,
    rq.score,
    rq.viewcount,
    rq.answercount,
    coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
    coalesce(va.bounty_awarded,0) as bounty_awarded,
    coalesce(e.edits,0) as edits,
    coalesce(e.closes,0) as closes,
    e.last_edit_date,
    e.first_close_date,
    dc.dup_inbound,
    dc.linked_inbound,
    array_length(string_to_array(coalesce(substring(rq.tags, 2, length(rq.tags)-2),''), '><'), 1) as tag_count
  from recent_questions rq
  left join votes_agg va on va.postid = rq.question_id
  left join edit_events e on e.postid = rq.question_id
  left join dup_clusters dc on dc.canonical_id = rq.question_id
),
hot_candidates as (
  select
    qm.*,
    case
      when qm.viewcount >= coalesce(tq.p90_views, 0) then 1 else 0
    end as high_view_flag,
    tq.avg_q_score,
    tq.q_count as tag_q_count
  from question_metrics qm
  left join lateral (
    select
      avg(tq.avg_q_score) as avg_q_score,
      avg(tq.p90_views) as p90_views,
      sum(tq.q_count) as q_count
    from tag_quality tq
    join tag_splits ts on ts.tag = tq.tag and ts.question_id = qm.question_id
  ) tq on true
),
ranked_questions as (
  select
    hc.question_id,
    hc.title,
    hc.tags,
    hc.creationdate,
    hc.score,
    hc.viewcount,
    hc.answercount,
    hc.net_votes,
    hc.bounty_awarded,
    hc.edits,
    hc.closes,
    hc.last_edit_date,
    hc.first_close_date,
    hc.dup_inbound,
    hc.linked_inbound,
    hc.tag_count,
    hc.high_view_flag,
    hc.avg_q_score,
    hc.tag_q_count,
    (
      coalesce(hc.net_votes,0)*1.0
      + ln(1 + greatest(hc.viewcount,0)) * 0.8
      + coalesce(hc.bounty_awarded,0) * 0.05
      + case when hc.answercount = 0 then 2.0 else 0.0 end
      - coalesce(hc.closes,0) * 1.5
      - coalesce(hc.dup_inbound,0) * 0.7
      + case when hc.high_view_flag = 1 then 3.0 else 0.0 end
      + coalesce(hc.avg_q_score,0) * 0.3
      + case when hc.tag_count between 2 and 4 then 0.5 else 0 end
      + least(length(coalesce(hc.title,'')) / 100.0, 1.0)
    ) as composite_score,
    row_number() over (
      partition by date_trunc('month', hc.creationdate)
      order by
        (
          coalesce(hc.net_votes,0)*1.0
          + ln(1 + greatest(hc.viewcount,0)) * 0.8
          + coalesce(hc.bounty_awarded,0) * 0.05
          + case when hc.answercount = 0 then 2.0 else 0.0 end
          - coalesce(hc.closes,0) * 1.5
          - coalesce(hc.dup_inbound,0) * 0.7
          + case when hc.high_view_flag = 1 then 3.0 else 0.0 end
          + coalesce(hc.avg_q_score,0) * 0.3
          + case when hc.tag_count between 2 and 4 then 0.5 else 0 end
          + least(length(coalesce(hc.title,'')) / 100.0, 1.0)
        ) desc,
        hc.viewcount desc,
        hc.score desc,
        hc.question_id
    ) as month_rank
  from hot_candidates hc
),
top_per_month as (
  select *
  from ranked_questions
  where month_rank <= 20
),
author_enrichment as (
  select
    p.id as post_id,
    u.id as author_id,
    u.displayname as author_name,
    u.reputation as author_reputation,
    ua.net_votes_cast as author_net_votes_cast,
    ua.badge_weight as author_badge_weight,
    ua.posts_authored as author_posts_authored,
    row_number() over (partition by p.id order by u.reputation desc nulls last) as author_rank
  from posts p
  left join users u on u.id = p.owneruserid
  left join user_activity ua on ua.user_id = u.id
)
select
  cast(tpm.creationdate as date) as month_day,
  tpm.question_id,
  tpm.title,
  tpm.tags,
  tpm.viewcount,
  tpm.score,
  tpm.answercount,
  tpm.net_votes,
  tpm.edits,
  tpm.closes,
  tpm.dup_inbound,
  tpm.linked_inbound,
  tpm.tag_count,
  round(cast(tpm.composite_score as numeric), 3) as composite_score,
  tpm.month_rank,
  coalesce(string_agg(distinct ts.tag, ',' order by ts.tag), '') as tag_list,
  coalesce(ae.author_id, -1) as author_id,
  coalesce(ae.author_name, '[deleted]') as author_name,
  coalesce(ae.author_reputation, 0) as author_reputation,
  coalesce(ae.author_net_votes_cast, 0) as author_net_votes_cast,
  coalesce(ae.author_badge_weight, 0) as author_badge_weight,
  coalesce(ae.author_posts_authored, 0) as author_posts_authored,
  ap.answers_given,
  ap.accepted_answers,
  round(coalesce(ap.avg_answer_score,0), 3) as avg_answer_score,
  round(coalesce(ap.pos_ratio,0), 3) as answer_pos_ratio
from top_per_month tpm
left join tag_splits ts on ts.question_id = tpm.question_id
left join author_enrichment ae on ae.post_id = tpm.question_id and ae.author_rank = 1
left join answerer_perf ap on ap.answerer_id = ae.author_id
group by
  tpm.creationdate,
  tpm.question_id,
  tpm.title,
  tpm.tags,
  tpm.viewcount,
  tpm.score,
  tpm.answercount,
  tpm.net_votes,
  tpm.edits,
  tpm.closes,
  tpm.dup_inbound,
  tpm.linked_inbound,
  tpm.tag_count,
  tpm.composite_score,
  tpm.month_rank,
  ae.author_id,
  ae.author_name,
  ae.author_reputation,
  ae.author_net_votes_cast,
  ae.author_badge_weight,
  ae.author_posts_authored,
  ap.answers_given,
  ap.accepted_answers,
  ap.avg_answer_score,
  ap.pos_ratio
order by date_trunc('month', tpm.creationdate) desc, tpm.month_rank asc, tpm.question_id asc;