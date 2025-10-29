-- {"query": "884.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2963} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
    extract(year from u.creationdate) as signup_year,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_global
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_counts as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    count(*) as total_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_posts as (
  select
    p.owneruserid as userid,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    count(*) filter (where p.posttypeid not in (1,2) or p.posttypeid is null) as other_count,
    sum(coalesce(p.score,0)) as total_score,
    avg(nullif(p.viewcount,0)) as avg_views_nonzero,
    max(p.creationdate) as last_post_date,
    sum(case when p.closeddate is not null then 1 else 0 end) as closed_q_count
  from posts p
  group by p.owneruserid
),
post_activity as (
  select
    p.id as post_id,
    p.owneruserid as userid,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    count(c.id) as comment_count,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
  from posts p
  left join comments c on c.postid = p.id
  left join votes v on v.postid = p.id
  group by p.id, p.owneruserid, p.posttypeid, p.creationdate, p.score, p.viewcount, p.title, p.tags
),
user_recent_activity as (
  select
    pa.userid,
    count(*) filter (where pa.creationdate >= now() - interval '30 days') as posts_30d,
    sum(pa.upvotes) filter (where pa.creationdate >= now() - interval '30 days') as up_30d,
    sum(pa.downvotes) filter (where pa.creationdate >= now() - interval '30 days') as down_30d,
    sum(pa.comment_count) filter (where pa.creationdate >= now() - interval '30 days') as comments_30d
  from post_activity pa
  group by pa.userid
),
dup_links as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.creationdate,
    row_number() over (partition by pl.postid order by pl.creationdate desc, pl.id desc) as rn
  from postlinks pl
  where pl.linktypeid = 3
),
question_quality as (
  select
    p.id as question_id,
    p.owneruserid as userid,
    p.score,
    p.viewcount,
    p.answercount,
    p.acceptedanswerid,
    case when p.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    coalesce(nullif(p.title, ''), '(untitled)') as normalized_title,
    length(coalesce(p.body,'')) as body_len,
    array_length(string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><'), 1) as tag_count,
    d.relatedpostid as marked_duplicate_of,
    case when d.rn = 1 then 1 else 0 end as is_recent_duplicate
  from posts p
  left join dup_links d on d.postid = p.id and d.rn = 1
  where p.posttypeid = 1
),
edit_events as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13)) as mod_events,
    sum(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+' then 1 else 0 end) as close_votes_with_reason
  from posthistory ph
  group by ph.postid
),
user_rankings as (
  select
    ru.id as userid,
    ru.displayname,
    ru.reputation,
    ru.signup_year,
    coalesce(bc.total_badges,0) as total_badges,
    coalesce(bc.gold_count,0) as gold_count,
    coalesce(bc.silver_count,0) as silver_count,
    coalesce(bc.bronze_count,0) as bronze_count,
    coalesce(up.q_count,0) as q_count,
    coalesce(up.a_count,0) as a_count,
    coalesce(up.other_count,0) as other_count,
    coalesce(up.total_score,0) as total_post_score,
    coalesce(up.avg_views_nonzero,0) as avg_views_nonzero,
    coalesce(ura.posts_30d,0) as posts_30d,
    coalesce(ura.up_30d,0) as up_30d,
    coalesce(ura.down_30d,0) as down_30d,
    coalesce(ura.comments_30d,0) as comments_30d,
    case
      when coalesce(up.q_count,0) + coalesce(up.a_count,0) = 0 then null
      else round((coalesce(up.a_count,0)::numeric / nullif(coalesce(up.q_count,0) + coalesce(up.a_count,0),0)) * 100, 2)
    end as answer_ratio_pct,
    row_number() over (
      order by
        coalesce(bc.gold_count,0) desc,
        coalesce(up.total_score,0) desc,
        ru.reputation desc,
        ru.id
    ) as merit_rank
  from recent_users ru
  left join badge_counts bc on bc.userid = ru.id
  left join user_posts up on up.userid = ru.id
  left join user_recent_activity ura on ura.userid = ru.id
),
top_users as (
  select *
  from user_rankings
  where merit_rank <= 200
),
question_metrics as (
  select
    qq.userid,
    count(*) as questions,
    sum(case when qq.has_accepted = 1 then 1 else 0 end) as accepted_qs,
    sum(case when qq.is_recent_duplicate = 1 then 1 else 0 end) as recent_dups,
    avg(qq.score) as avg_q_score,
    percentile_disc(0.5) within group (order by qq.viewcount) as med_q_views,
    avg(qq.tag_count) as avg_tag_count,
    sum(case when ee.edits > 0 then 1 else 0 end) as edited_qs
  from question_quality qq
  left join edit_events ee on ee.postid = qq.question_id
  group by qq.userid
),
answer_metrics as (
  select
    p.owneruserid as userid,
    count(*) as answers,
    avg(p.score) as avg_a_score,
    sum(case when p.parentid is not null and p.score > 0 then 1 else 0 end) as positive_answers,
    sum(case when p.parentid is not null and p.creationdate >= now() - interval '90 days' then 1 else 0 end) as answers_90d
  from posts p
  where p.posttypeid = 2
  group by p.owneruserid
),
engagement as (
  select
    u.id as userid,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
    sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
    count(c.id) as total_comments,
    max(c.creationdate) as last_comment_date
  from users u
  left join comments c on c.userid = u.id
  group by u.id
),
normalized_locations as (
  select
    u.id as userid,
    case
      when u.location ilike '%united states%' or u.location ilike '%usa%' or u.location ilike '%u.s.%' then 'USA'
      when u.location ilike '%india%' then 'India'
      when u.location ilike '%united kingdom%' or u.location ilike '%uk%' or u.location ilike '%england%' then 'UK'
      when u.location ilike '%germany%' then 'Germany'
      when u.location ilike '%canada%' then 'Canada'
      when u.location is null or trim(u.location) = '' then 'Unknown'
      else 'Other'
    end as country_bucket
  from users u
)
select
  tu.userid,
  tu.displayname,
  tu.reputation,
  tu.signup_year,
  tu.merit_rank,
  tu.total_badges,
  tu.gold_count,
  tu.silver_count,
  tu.bronze_count,
  tu.q_count,
  tu.a_count,
  tu.other_count,
  tu.total_post_score,
  tu.avg_views_nonzero,
  tu.posts_30d,
  tu.up_30d,
  tu.down_30d,
  tu.comments_30d,
  tu.answer_ratio_pct,
  coalesce(qm.questions,0) as questions,
  coalesce(qm.accepted_qs,0) as accepted_qs,
  coalesce(qm.recent_dups,0) as recent_dups,
  coalesce(qm.avg_q_score,0) as avg_q_score,
  coalesce(qm.med_q_views,0) as med_q_views,
  coalesce(qm.avg_tag_count,0) as avg_tag_count,
  coalesce(qm.edited_qs,0) as edited_qs,
  coalesce(am.answers,0) as answers,
  coalesce(am.avg_a_score,0) as avg_a_score,
  coalesce(am.positive_answers,0) as positive_answers,
  coalesce(am.answers_90d,0) as answers_90d,
  coalesce(e.pos_comments,0) as pos_comments,
  coalesce(e.neg_comments,0) as neg_comments,
  coalesce(e.total_comments,0) as total_comments,
  e.last_comment_date,
  nl.country_bucket,
  case
    when tu.gold_count > 0 and coalesce(qm.accepted_qs,0) > 0 then 'GoldMentor'
    when tu.silver_count > 3 and coalesce(am.answers,0) > 50 then 'SilverAnswerer'
    when tu.bronze_count > 10 and coalesce(qm.questions,0) > 10 then 'BronzeInquisitor'
    else 'Rising'
  end as profile_archetype,
  case
    when coalesce(qm.questions,0) = 0 then null
    else round((coalesce(qm.accepted_qs,0)::numeric / nullif(qm.questions,0)) * 100, 2)
  end as q_accept_rate_pct,
  case
    when coalesce(e.total_comments,0) = 0 then 0
    else round((coalesce(e.pos_comments,0)::numeric - coalesce(e.neg_comments,0)::numeric) / nullif(e.total_comments,0), 3)
  end as comment_sentiment_index,
  (
    select string_agg(distinct trim(both '<>' from t), ', ' order by lower(t))
    from (
      select unnest(string_to_array(coalesce(substring(p.tags, 2, length(p.tags)-2), ''), '><')) as t
      from posts p
      where p.owneruserid = tu.userid and p.posttypeid = 1
      order by p.creationdate desc
      limit 200
    ) s
  ) as recent_question_tags,
  (
    select count(*)
    from votes v
    where v.userid = tu.userid
      and v.votetypeid in (2,3)
      and v.creationdate >= now() - interval '180 days'
  ) as cast_votes_180d
from top_users tu
left join question_metrics qm on qm.userid = tu.userid
left join answer_metrics am on am.userid = tu.userid
left join engagement e on e.userid = tu.userid
left join normalized_locations nl on nl.userid = tu.userid
where
  (
    coalesce(qm.questions,0) + coalesce(am.answers,0)
  ) > 0
  and (
    tu.reputation > 1000
    or (tu.gold_count > 0 and coalesce(qm.avg_q_score,0) > 1)
    or (tu.a_count > tu.q_count and coalesce(am.avg_a_score,0) > 0)
  )
order by
  tu.merit_rank asc,
  tu.userid
limit 100;