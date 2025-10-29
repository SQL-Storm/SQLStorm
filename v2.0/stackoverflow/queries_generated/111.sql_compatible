with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    u.websiteurl,
    coalesce(nullif(trim(u.aboutme), ''), '[none]') as aboutme_norm,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
active_questions as (
  select
    p.id as question_id,
    p.owneruserid as owner_user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    p.closeddate,
    p.communityowneddate,
    p.acceptedanswerid,
    case when p.closeddate is not null then 1 else 0 end as is_closed,
    case when p.acceptedanswerid is not null then 1 else 0 end as has_accepted
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as owner_user_id,
    a.creationdate,
    a.score as answer_score
  from posts a
  where a.posttypeid = 2
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag_name
  from active_questions q
  where q.tags is not null and q.tags <> ''
),
question_votes as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    count(*) as total_votes
  from votes v
  join active_questions q on q.question_id = v.postid
  group by v.postid
),
comment_pings as (
  select
    c.postid as post_id,
    count(*) filter (where c.text ilike '%@%') as at_mentions,
    count(*) as total_comments,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
postlinks_dedupe as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.linktypeid,
    min(pl.creationdate) as first_link_at
  from postlinks pl
  group by pl.postid, pl.relatedpostid, pl.linktypeid
),
duplicate_graph as (
  select
    q.question_id,
    count(*) filter (where pl.linktypeid = 3) as dup_out_count,
    count(*) filter (where pl.linktypeid = 1) as link_out_count,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as dup_out_distinct,
    count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as link_out_distinct,
    min(case when pl.linktypeid = 3 then pl.first_link_at end) as first_dup_at
  from active_questions q
  left join postlinks_dedupe pl on pl.postid = q.question_id
  group by q.question_id
),
user_badge_summaries as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
question_first_answer as (
  select
    a.question_id,
    min(a.creationdate) as first_answer_at,
    count(*) as answer_count_total
  from answers a
  group by a.question_id
),
owner_activity as (
  select
    u.id as user_id,
    count(*) filter (where p.posttypeid = 1) as questions_posted,
    count(*) filter (where p.posttypeid = 2) as answers_posted,
    sum(coalesce(p.score,0)) as total_post_score,
    count(*) as total_posts
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
edit_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_count,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events
  from posthistory ph
  group by ph.postid
),
question_quality as (
  select
    q.question_id,
    q.score,
    q.viewcount,
    q.answercount,
    q.has_accepted,
    q.is_closed,
    coalesce(qv.net_votes, 0) as net_votes,
    coalesce(qv.upvotes, 0) as upvotes,
    coalesce(qv.downvotes, 0) as downvotes,
    coalesce(cp.total_comments, 0) as total_comments,
    coalesce(cp.at_mentions, 0) as at_mentions,
    coalesce(dg.dup_out_count, 0) as dup_out_count,
    coalesce(dg.link_out_count, 0) as link_out_count,
    coalesce(dg.dup_out_distinct, 0) as dup_out_distinct,
    coalesce(dg.link_out_distinct, 0) as link_out_distinct,
    coalesce(qfa.answer_count_total, 0) as answer_count_total,
    case
      when q.viewcount is null or q.viewcount = 0 then null
      else round((cast(q.score as numeric) / nullif(q.viewcount,0)) * 1000, 3)
    end as score_per_kview,
    case
      when qfa.first_answer_at is null then null
      else cast(extract(epoch from (qfa.first_answer_at - q.creationdate)) as bigint)
    end as seconds_to_first_answer,
    case
      when q.viewcount is null then 0
      when q.viewcount > 10000 then 3
      when q.viewcount > 1000 then 2
      when q.viewcount > 100 then 1
      else 0
    end as popularity_bucket
  from active_questions q
  left join question_votes qv on qv.question_id = q.question_id
  left join comment_pings cp on cp.post_id = q.question_id
  left join duplicate_graph dg on dg.question_id = q.question_id
  left join question_first_answer qfa on qfa.question_id = q.question_id
),
tag_stats as (
  select
    t.tag_name,
    count(distinct t.question_id) as questions_with_tag,
    sum(qq.answer_count_total) as total_answers_for_tag,
    sum(qq.has_accepted) as accepted_count_for_tag,
    avg(qq.seconds_to_first_answer) filter (where qq.seconds_to_first_answer is not null) as avg_secs_to_first_answer,
    percentile_disc(0.5) within group (order by qq.seconds_to_first_answer) as median_secs_to_first_answer,
    avg(qq.score_per_kview) as avg_score_per_kview
  from tag_expansion t
  join question_quality qq on qq.question_id = t.question_id
  group by t.tag_name
),
question_owner as (
  select
    q.question_id,
    u.id as owner_user_id,
    u.displayname as owner_displayname,
    u.reputation as owner_reputation,
    ua.total_badges,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    oa.questions_posted,
    oa.answers_posted,
    oa.total_post_score
  from active_questions q
  left join users u on u.id = q.owner_user_id
  left join user_badge_summaries ua on ua.userid = u.id
  left join owner_activity oa on oa.user_id = u.id
),
ranked_questions as (
  select
    qq.*,
    qo.owner_user_id,
    qo.owner_displayname,
    qo.owner_reputation,
    qo.total_badges,
    qo.gold_badges,
    qo.silver_badges,
    qo.bronze_badges,
    qo.questions_posted,
    qo.answers_posted,
    qo.total_post_score,
    row_number() over (order by coalesce(qq.score_per_kview, -1) desc, qq.viewcount desc) as rn_by_efficiency,
    row_number() over (order by qq.viewcount desc, qq.score desc) as rn_by_popularity,
    dense_rank() over (order by qq.net_votes desc) as dr_by_net_votes
  from question_quality qq
  left join question_owner qo on qo.question_id = qq.question_id
),
cohort_performance as (
  select
    ru.cohort_month,
    count(distinct ru.user_id) as users_in_cohort,
    avg(ru.reputation) as avg_rep_on_join,
    sum(case when ru.websiteurl is null or ru.websiteurl = '' then 1 else 0 end) as no_website_count
  from recent_users ru
  group by ru.cohort_month
),
final_agg as (
  select
    rq.question_id,
    rq.owner_user_id,
    rq.owner_displayname,
    rq.owner_reputation,
    rq.total_badges,
    rq.gold_badges,
    rq.silver_badges,
    rq.bronze_badges,
    rq.questions_posted,
    rq.answers_posted,
    rq.total_post_score,
    rq.score,
    rq.viewcount,
    rq.answercount,
    rq.has_accepted,
    rq.is_closed,
    rq.net_votes,
    rq.upvotes,
    rq.downvotes,
    rq.total_comments,
    rq.at_mentions,
    rq.dup_out_count,
    rq.link_out_count,
    rq.dup_out_distinct,
    rq.link_out_distinct,
    rq.answer_count_total,
    rq.score_per_kview,
    rq.seconds_to_first_answer,
    rq.popularity_bucket,
    rq.rn_by_efficiency,
    rq.rn_by_popularity,
    rq.dr_by_net_votes,
    ts_top.tag_name as top_tag_by_median_time,
    ts_top.median_secs_to_first_answer as top_tag_median_secs,
    ts_pop.tag_name as top_tag_by_questions,
    ts_pop.questions_with_tag as top_tag_questions
  from ranked_questions rq
  left join lateral (
    select t2.tag_name, ts.median_secs_to_first_answer
    from tag_expansion t2
    join tag_stats ts on ts.tag_name = t2.tag_name
    where t2.question_id = rq.question_id
    order by ts.median_secs_to_first_answer nulls last, ts.questions_with_tag desc
    limit 1
  ) ts_top on true
  left join lateral (
    select t3.tag_name, ts.questions_with_tag
    from tag_expansion t3
    join tag_stats ts on ts.tag_name = t3.tag_name
    where t3.question_id = rq.question_id
    order by ts.questions_with_tag desc, t3.tag_name
    limit 1
  ) ts_pop on true
)
select
  fa.*,
  cr.cohort_month,
  cr.users_in_cohort,
  cr.avg_rep_on_join,
  cr.no_website_count,
  case
    when fa.has_accepted = 1 and fa.seconds_to_first_answer is not null and fa.seconds_to_first_answer < 3600 then 'fast accept'
    when fa.has_accepted = 1 then 'accepted'
    when fa.answercount > 0 then 'answered'
    when fa.is_closed = 1 then 'closed'
    else 'open-unanswered'
  end as resolution_class,
  case
    when fa.owner_displayname is null then 'anonymous'
    when position(' ' in fa.owner_displayname) > 0 then split_part(fa.owner_displayname, ' ', 1)
    else fa.owner_displayname
  end as owner_name_first_token
from final_agg fa
left join lateral (
  select
    cp.cohort_month,
    cp.users_in_cohort,
    cp.avg_rep_on_join,
    cp.no_website_count
  from cohort_performance cp
  order by cp.cohort_month desc
  limit 1
) cr on true
where
  (
    fa.rn_by_efficiency <= 100
    or fa.rn_by_popularity <= 100
    or fa.dr_by_net_votes <= 100
  )
  and coalesce(fa.viewcount, 0) + coalesce(fa.answercount, 0) + coalesce(fa.total_comments, 0) > 0
  and (
    coalesce(fa.upvotes, 0) >= coalesce(fa.downvotes, 0)
    or fa.downvotes is null
  )
order by
  fa.rn_by_efficiency,
  fa.rn_by_popularity,
  fa.dr_by_net_votes,
  fa.question_id
limit 500;