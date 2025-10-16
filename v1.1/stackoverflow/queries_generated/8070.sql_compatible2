with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.location,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
         row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (
    select date_trunc('month', max(creationdate)) - interval '6 months' from users
  )
),
tagged_questions as (
  select p.id as question_id,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         string_to_array(substring(p.tags from 2 for (length(p.tags) - 2)), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (
      select date_trunc('month', max(creationdate)) - interval '12 months' from posts where posttypeid = 1
    )
),
answers as (
  select a.id as answer_id,
         a.parentid as question_id,
         a.owneruserid as answerer_id,
         a.score as answer_score,
         a.creationdate as answer_date
  from posts a
  where a.posttypeid = 2
),
votes_rollup as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
         min(v.creationdate) as first_vote_date,
         max(v.creationdate) as last_vote_date
  from votes v
  group by v.postid
),
question_stats as (
  select q.question_id,
         q.owneruserid,
         q.creationdate,
         q.score,
         q.viewcount,
         q.title,
         q.tag_arr,
         vr.upvotes,
         vr.downvotes,
         vr.favorites,
         vr.bounty_total,
         coalesce(vr.upvotes,0) - coalesce(vr.downvotes,0) as net_votes,
         count(a.answer_id) as answer_count,
         max(a.answer_score) filter (where a.answer_id is not null) as max_answer_score,
         min(a.answer_date) filter (where a.answer_id is not null) as first_answer_date,
         max(a.answer_date) filter (where a.answer_id is not null) as last_answer_date
  from tagged_questions q
  left join answers a
    on a.question_id = q.question_id
  left join votes_rollup vr
    on vr.postid = q.question_id
  group by q.question_id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tag_arr, vr.upvotes, vr.downvotes, vr.favorites, vr.bounty_total
),
user_activity as (
  select u.id as user_id,
         count(distinct case when p.posttypeid = 1 then p.id end) as question_posts,
         count(distinct case when p.posttypeid = 2 then p.id end) as answer_posts,
         sum(coalesce(p.score,0)) as total_post_score,
         sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as total_upmods_given,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as total_downmods_given,
         max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  left join votes v on v.userid = u.id
  group by u.id
),
badge_rollup as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         count(*) as total_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
tag_popularity as (
  select t.tagname,
         t.count as tag_total_count,
         t.ismoderatoronly,
         t.isrequired
  from tags t
),
question_tag_expanded as (
  select qs.question_id,
         qs.owneruserid,
         qs.creationdate,
         qs.score,
         qs.viewcount,
         qs.title,
         unnest(qs.tag_arr) as tagname,
         qs.upvotes,
         qs.downvotes,
         qs.favorites,
         qs.bounty_total,
         qs.net_votes,
         qs.answer_count,
         qs.max_answer_score,
         qs.first_answer_date,
         qs.last_answer_date
  from question_stats qs
),
owner_user_enriched as (
  select r.user_id,
         r.displayname,
         r.reputation,
         r.creationdate as user_creationdate,
         r.location,
         r.websiteurl_norm,
         ua.question_posts,
         ua.answer_posts,
         ua.total_post_score,
         ua.total_question_views,
         ua.total_upmods_given,
         ua.total_downmods_given,
         br.gold_badges,
         br.silver_badges,
         br.bronze_badges,
         br.total_badges,
         br.last_badge_date
  from recent_users r
  left join user_activity ua on ua.user_id = r.user_id
  left join badge_rollup br on br.userid = r.user_id
  where r.rn <= 500
),
question_with_owner as (
  select qte.question_id,
         qte.owneruserid,
         qte.creationdate,
         qte.score,
         qte.viewcount,
         qte.title,
         qte.tagname,
         qte.upvotes,
         qte.downvotes,
         qte.favorites,
         qte.bounty_total,
         qte.net_votes,
         qte.answer_count,
         qte.max_answer_score,
         qte.first_answer_date,
         qte.last_answer_date,
         oue.displayname as owner_displayname,
         oue.reputation as owner_reputation,
         oue.location as owner_location,
         oue.websiteurl_norm as owner_website,
         oue.question_posts as owner_questions,
         oue.answer_posts as owner_answers,
         oue.total_post_score as owner_total_post_score,
         oue.total_badges as owner_total_badges
  from question_tag_expanded qte
  left join owner_user_enriched oue
    on oue.user_id = qte.owneruserid
),
dup_links as (
  select pl.postid as duplicate_of_id,
         count(*) as dup_count
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid
),
close_events as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
         max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_event_date,
         max(case when ph.posthistorytypeid = 10 then nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') end) as last_close_reason_id_text
  from posthistory ph
  group by ph.postid
),
accepted_map as (
  select q.id as question_id,
         q.acceptedanswerid,
         a.owneruserid as accepted_owner_id,
         a.score as accepted_answer_score
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1
),
per_tag_agg as (
  select
    qwo.tagname,
    count(distinct qwo.question_id) as questions,
    sum(coalesce(qwo.answer_count,0)) as answers,
    avg(nullif(qwo.viewcount,0)) as avg_views,
    percentile_cont(0.5) within group (order by coalesce(qwo.net_votes,0)) as p50_net_votes,
    max(qwo.bounty_total) as max_bounty_on_q,
    sum(case when qwo.owner_reputation >= 10000 then 1 else 0 end) as questions_by_high_rep,
    sum(case when qwo.owner_total_badges >= 50 then 1 else 0 end) as questions_by_decorated,
    sum(case when qwo.score > 0 and qwo.answer_count > 0 then 1 else 0 end) as positively_scored_answered,
    count(distinct case when qwo.first_answer_date is not null and qwo.first_answer_date <= qwo.creationdate + interval '1 day' then qwo.question_id end) as answered_within_1d
  from question_with_owner qwo
  group by qwo.tagname
),
recent_q_enriched as (
  select
    qwo.question_id,
    qwo.tagname,
    qwo.title,
    qwo.creationdate,
    qwo.viewcount,
    qwo.score,
    qwo.upvotes,
    qwo.downvotes,
    qwo.net_votes,
    qwo.answer_count,
    qwo.max_answer_score,
    qwo.first_answer_date,
    qwo.last_answer_date,
    tm.tag_total_count,
    tm.ismoderatoronly,
    tm.isrequired,
    coalesce(da.dup_count,0) as dup_count,
    coalesce(ce.close_votes_events,0) as close_events,
    ce.last_close_event_date,
    case when ce.last_close_reason_id_text ~ '^[0-9]+$' then cast(ce.last_close_reason_id_text as integer) else null end as last_close_reason_id,
    am.acceptedanswerid,
    am.accepted_owner_id,
    am.accepted_answer_score,
    qwo.owner_displayname,
    qwo.owner_reputation,
    qwo.owner_location,
    qwo.owner_website,
    qwo.owner_questions,
    qwo.owner_answers,
    qwo.owner_total_post_score,
    qwo.owner_total_badges
  from question_with_owner qwo
  left join tag_popularity tm on lower(tm.tagname) = lower(qwo.tagname)
  left join dup_links da on da.duplicate_of_id = qwo.question_id
  left join close_events ce on ce.postid = qwo.question_id
  left join accepted_map am on am.question_id = qwo.question_id
),
ranked_q as (
  select
    rqe.question_id,
    rqe.tagname,
    rqe.title,
    rqe.creationdate,
    rqe.viewcount,
    rqe.score,
    rqe.upvotes,
    rqe.downvotes,
    rqe.net_votes,
    rqe.answer_count,
    rqe.max_answer_score,
    rqe.first_answer_date,
    rqe.last_answer_date,
    rqe.tag_total_count,
    rqe.ismoderatoronly,
    rqe.isrequired,
    rqe.dup_count,
    rqe.close_events,
    rqe.last_close_event_date,
    rqe.last_close_reason_id,
    rqe.acceptedanswerid,
    rqe.accepted_owner_id,
    rqe.accepted_answer_score,
    rqe.owner_displayname,
    rqe.owner_reputation,
    rqe.owner_location,
    rqe.owner_website,
    rqe.owner_questions,
    rqe.owner_answers,
    rqe.owner_total_post_score,
    rqe.owner_total_badges,
    row_number() over (partition by rqe.tagname order by coalesce(rqe.net_votes, -999999) desc, rqe.viewcount desc, rqe.creationdate desc) as rank_in_tag,
    dense_rank() over (order by coalesce(rqe.net_votes, -999999) desc) as global_net_vote_rank,
    ntile(10) over (order by coalesce(rqe.viewcount,0) desc) as view_ntile_10,
    sum(coalesce(rqe.answer_count,0)) over (partition by rqe.tagname order by rqe.creationdate rows between unbounded preceding and current row) as running_answers_in_tag
  from recent_q_enriched rqe
),
filtered_ranked as (
  select *
  from ranked_q
  where (rank_in_tag <= 25 or global_net_vote_rank <= 100)
    and (coalesce(ismoderatoronly, false) = false or ismoderatoronly is null)
    and (tagname is not null and length(tagname) between 1 and 35)
),
tag_summaries as (
  select
    pt.tagname,
    pt.questions,
    pt.answers,
    pt.avg_views,
    pt.p50_net_votes,
    pt.max_bounty_on_q,
    pt.questions_by_high_rep,
    pt.questions_by_decorated
  from per_tag_agg pt
  where pt.questions >= 5
),
final_set as (
  select
    fr.tagname,
    fr.question_id,
    fr.title,
    fr.creationdate,
    fr.viewcount,
    fr.score,
    fr.upvotes,
    fr.downvotes,
    fr.net_votes,
    fr.answer_count,
    fr.max_answer_score,
    fr.first_answer_date,
    fr.last_answer_date,
    fr.dup_count,
    fr.close_events,
    fr.last_close_event_date,
    fr.last_close_reason_id,
    fr.acceptedanswerid,
    fr.accepted_owner_id,
    fr.accepted_answer_score,
    fr.owner_displayname,
    fr.owner_reputation,
    fr.owner_location,
    fr.owner_website,
    fr.owner_questions,
    fr.owner_answers,
    fr.owner_total_post_score,
    fr.owner_total_badges,
    fr.rank_in_tag,
    fr.global_net_vote_rank,
    fr.view_ntile_10,
    fr.running_answers_in_tag,
    ts.questions as tag_total_questions,
    ts.answers as tag_total_answers,
    ts.avg_views as tag_avg_views,
    ts.p50_net_votes as tag_p50_net_votes,
    ts.max_bounty_on_q as tag_max_bounty,
    ts.questions_by_high_rep,
    ts.questions_by_decorated
  from filtered_ranked fr
  left join tag_summaries ts on ts.tagname = fr.tagname
),
popular_vs_required as (
  select
    fs.*,
    case
      when coalesce(fs.tag_total_questions,0) > 1000 and coalesce(fs.questions_by_high_rep,0) > 50 then 'popular'
      when coalesce(fs.tag_total_questions,0) <= 1000 and coalesce(fs.questions_by_high_rep,0) <= 50 then 'niche'
      else 'mixed'
    end as popularity_bucket
  from final_set fs
)
select *
from (
  select
    pvr.tagname,
    pvr.question_id,
    pvr.title,
    pvr.creationdate,
    pvr.viewcount,
    pvr.score,
    pvr.upvotes,
    pvr.downvotes,
    pvr.net_votes,
    pvr.answer_count,
    pvr.max_answer_score,
    pvr.first_answer_date,
    pvr.last_answer_date,
    pvr.dup_count,
    pvr.close_events,
    pvr.last_close_event_date,
    pvr.last_close_reason_id,
    pvr.acceptedanswerid,
    pvr.accepted_owner_id,
    pvr.accepted_answer_score,
    pvr.owner_displayname,
    pvr.owner_reputation,
    pvr.owner_location,
    pvr.owner_website,
    pvr.owner_questions,
    pvr.owner_answers,
    pvr.owner_total_post_score,
    pvr.owner_total_badges,
    pvr.rank_in_tag,
    pvr.global_net_vote_rank,
    pvr.view_ntile_10,
    pvr.running_answers_in_tag,
    pvr.tag_total_questions,
    pvr.tag_total_answers,
    pvr.tag_avg_views,
    pvr.tag_p50_net_votes,
    pvr.tag_max_bounty,
    pvr.questions_by_high_rep,
    pvr.questions_by_decorated,
    case
      when pvr.acceptedanswerid is not null and coalesce(pvr.answer_count,0) = 0 then 'data_inconsistency'
      when pvr.acceptedanswerid is not null then 'has_accepted'
      when pvr.answer_count > 0 then 'has_answers'
      else 'unanswered'
    end as answer_status,
    case
      when pvr.owner_website like 'http%' then 'has_site'
      when pvr.owner_website similar to '%[.][a-zA-Z]{2,}$' then 'has_site'
      when pvr.owner_website is null or pvr.owner_website in ('', 'n/a') then 'no_site'
      else 'unknown'
    end as website_status,
    pvr.popularity_bucket
  from popular_vs_required pvr
  where (pvr.tag_total_questions is not null and pvr.tag_total_questions >= 5)
) x
where coalesce(x.net_votes, -100000) >= (
    select avg(coalesce(net_votes,0)) + stddev_pop(coalesce(net_votes,0))
    from recent_q_enriched
)
order by x.popularity_bucket, x.tagname, x.rank_in_tag, x.global_net_vote_rank
limit 500;