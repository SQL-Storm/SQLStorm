-- {"query": "515.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2934} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_agg as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_posts as (
    select p.id as question_id,
           p.owneruserid as q_owner_id,
           p.score as q_score,
           p.viewcount,
           p.creationdate as q_created,
           p.acceptedanswerid,
           p.title,
           p.tags,
           case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid as a_owner_id,
           a.score as a_score,
           a.creationdate as a_created
    from posts a
    where a.posttypeid = 2
),
answer_stats as (
    select ap.question_id,
           count(*) as answer_cnt,
           count(*) filter (where ap.a_score > 0) as pos_answer_cnt,
           max(ap.a_score) as max_answer_score,
           min(ap.a_score) as min_answer_score,
           avg(ap.a_score) as avg_answer_score,
           max(ap.a_created) as last_answer_date
    from answer_posts ap
    group by ap.question_id
),
accepted_answerers as (
    select q.question_id,
           ap.a_owner_id as accepted_owner_id
    from question_posts q
    join answer_posts ap
      on ap.answer_id = q.acceptedanswerid
),
votes_by_type as (
    select v.postid,
           v.votetypeid,
           count(*) as vote_count
    from votes v
    group by v.postid, v.votetypeid
),
question_vote_pivot as (
    select q.question_id,
           sum(case when vbt.votetypeid = 2 then vbt.vote_count else 0 end) as upvotes,
           sum(case when vbt.votetypeid = 3 then vbt.vote_count else 0 end) as downvotes,
           sum(case when vbt.votetypeid = 5 then vbt.vote_count else 0 end) as favorites
    from question_posts q
    left join votes_by_type vbt on vbt.postid = q.question_id
    group by q.question_id
),
duplicate_links as (
    select pl.postid as question_id,
           count(*) filter (where pl.linktypeid = 3) as duplicate_cnt,
           count(*) filter (where pl.linktypeid = 1) as linked_cnt
    from postlinks pl
    group by pl.postid
),
tag_explode as (
    select q.question_id,
           unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tag
    from question_posts q
),
tag_quality as (
    select te.tag,
           count(distinct te.question_id) as tagged_questions,
           avg(qp.q_score) as avg_q_score,
           percentile_cont(0.9) within group (order by qp.q_score) as p90_q_score
    from tag_explode te
    join question_posts qp on qp.question_id = te.question_id
    group by te.tag
),
post_history_flags as (
    select ph.postid as question_id,
           max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as was_closed_or_migrated,
           max(case when ph.posthistorytypeid in (11) then 1 else 0 end) as was_reopened,
           max(case when ph.posthistorytypeid in (24) then 1 else 0 end) as had_suggested_edit
    from posthistory ph
    group by ph.postid
),
comment_sentiment as (
    select c.postid as question_id,
           avg(c.score) as avg_comment_score,
           sum(case when position('thank' in lower(c.text)) > 0 then 1 else 0 end) as thanks_mentions,
           count(*) as comment_cnt
    from comments c
    group by c.postid
),
question_owner as (
    select q.question_id,
           u.id as owner_id,
           u.displayname as owner_name,
           u.reputation as owner_rep,
           u.location as owner_loc,
           ru.domain as owner_domain
    from question_posts q
    left join users u on u.id = q.q_owner_id
    left join recent_users ru on ru.user_id = u.id
),
answerer_diversity as (
    select ap.question_id,
           count(distinct ap.a_owner_id) as unique_answerers,
           count(*) as total_answers
    from answer_posts ap
    group by ap.question_id
),
q_rankings as (
    select q.question_id,
           q.q_score,
           q.viewcount,
           row_number() over (order by q.q_score desc, q.viewcount desc, q.question_id) as rn_score,
           row_number() over (order by q.viewcount desc, q.q_score desc, q.question_id) as rn_views,
           dense_rank() over (partition by coalesce(q.is_closed,0) order by q.q_score desc) as dr_by_closed
    from question_posts q
),
owner_activity as (
    select u.id as owner_id,
           count(*) filter (where p.posttypeid = 1) as questions_asked,
           count(*) filter (where p.posttypeid = 2) as answers_posted,
           sum(coalesce(p.score,0)) as total_post_score,
           max(p.lastactivitydate) as last_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
owner_quality_score as (
    select oa.owner_id,
           (0.5 * log(1 + coalesce(oa.questions_asked,0)) +
            0.7 * log(1 + coalesce(oa.answers_posted,0)) +
            0.3 * greatest(0, coalesce(oa.total_post_score,0)) / nullif(oa.answers_posted + oa.questions_asked,0)
           )::numeric(18,6) as quality_score
    from owner_activity oa
),
final_questions as (
    select q.question_id,
           q.title,
           q.tags,
           q.q_score,
           q.viewcount,
           q.q_created,
           q.acceptedanswerid,
           q.is_closed,
           qa.answer_cnt,
           qa.pos_answer_cnt,
           qa.max_answer_score,
           qa.min_answer_score,
           qa.avg_answer_score,
           qa.last_answer_date,
           qvp.upvotes,
           qvp.downvotes,
           qvp.favorites,
           coalesce(dl.duplicate_cnt,0) as duplicate_cnt,
           coalesce(dl.linked_cnt,0) as linked_cnt,
           ph.was_closed_or_migrated,
           ph.was_reopened,
           ph.had_suggested_edit,
           cs.avg_comment_score,
           cs.thanks_mentions,
           cs.comment_cnt,
           qo.owner_id,
           qo.owner_name,
           qo.owner_rep,
           qo.owner_loc,
           qo.owner_domain,
           aa.accepted_owner_id,
           ad.unique_answerers,
           ad.total_answers,
           qr.rn_score,
           qr.rn_views,
           qr.dr_by_closed
    from question_posts q
    left join answer_stats qa on qa.question_id = q.question_id
    left join question_vote_pivot qvp on qvp.question_id = q.question_id
    left join duplicate_links dl on dl.question_id = q.question_id
    left join post_history_flags ph on ph.question_id = q.question_id
    left join comment_sentiment cs on cs.question_id = q.question_id
    left join question_owner qo on qo.question_id = q.question_id
    left join accepted_answerers aa on aa.question_id = q.question_id
    left join answerer_diversity ad on ad.question_id = q.question_id
    left join q_rankings qr on qr.question_id = q.question_id
),
owner_enriched as (
    select fq.*,
           uba.badge_count,
           uba.gold_count,
           uba.silver_count,
           uba.bronze_count,
           uba.last_badge_date,
           oqs.quality_score,
           case
             when uba.gold_count > 0 then 'gold'
             when uba.silver_count > 0 then 'silver'
             when uba.bronze_count > 0 then 'bronze'
             else 'none'
           end as top_badge_class
    from final_questions fq
    left join user_badge_agg uba on uba.userid = fq.owner_id
    left join owner_quality_score oqs on oqs.owner_id = fq.owner_id
),
tag_best as (
    select te.question_id,
           max(tq.p90_q_score) as tag_p90_max,
           avg(tq.avg_q_score) as tag_avg_mean
    from tag_explode te
    join tag_quality tq on tq.tag = te.tag
    group by te.question_id
),
filter_recent_hot as (
    select oe.*,
           tb.tag_p90_max,
           tb.tag_avg_mean,
           case when oe.upvotes - oe.downvotes >= 0 then 1 else 0 end as non_negative_ratio,
           case
             when oe.acceptedanswerid is not null and oe.answer_cnt > 0 then 1
             else 0
           end as has_accept_and_answers
    from owner_enriched oe
    left join tag_best tb on tb.question_id = oe.question_id
    where oe.q_created >= (select max(creationdate) - interval '365 days' from posts)
)
select
    frh.question_id,
    frh.title,
    coalesce(frh.tags, '') as tags,
    frh.q_score,
    frh.viewcount,
    frh.upvotes,
    frh.downvotes,
    frh.favorites,
    frh.answer_cnt,
    frh.avg_answer_score,
    frh.unique_answerers,
    frh.owner_id,
    coalesce(frh.owner_name, concat('anon#', frh.owner_id::varchar)) as owner_name,
    coalesce(frh.owner_loc, 'n/a') as owner_loc,
    coalesce(frh.owner_domain, 'unknown') as owner_domain,
    coalesce(frh.badge_count, 0) as badge_count,
    coalesce(frh.gold_count, 0) as gold_badges,
    coalesce(frh.silver_count, 0) as silver_badges,
    coalesce(frh.bronze_count, 0) as bronze_badges,
    frh.top_badge_class,
    round(coalesce(frh.quality_score, 0)::numeric, 4) as owner_quality_score,
    frh.duplicate_cnt,
    frh.linked_cnt,
    frh.was_closed_or_migrated,
    frh.was_reopened,
    frh.had_suggested_edit,
    frh.avg_comment_score,
    frh.thanks_mentions,
    frh.comment_cnt,
    frh.tag_p90_max,
    frh.tag_avg_mean,
    frh.rn_score,
    frh.rn_views,
    frh.dr_by_closed,
    case
      when frh.is_closed = 1 then 'closed'
      when frh.viewcount > 100000 and frh.q_score > 50 then 'viral'
      when frh.viewcount > 50000 and frh.q_score > 25 then 'hot'
      when frh.viewcount > 10000 and frh.q_score > 10 then 'warm'
      else 'normal'
    end as heat_bucket,
    case
      when frh.non_negative_ratio = 1 and coalesce(frh.avg_comment_score, 0) >= 0 then 'non-toxic'
      when frh.downvotes > frh.upvotes then 'controversial'
      else 'mixed'
    end as sentiment_bucket,
    case
      when frh.has_accept_and_answers = 1 then 1
      when frh.answer_cnt > 2 and frh.avg_answer_score > 0 then 1
      else 0
    end as solved_indicator
from filter_recent_hot frh
where (
        frh.q_score > 5
        or (frh.upvotes - frh.downvotes) > 3
        or (frh.favorites is not null and frh.favorites > 5)
      )
  and coalesce(frh.tag_p90_max, 0) >= 0
  and (
        frh.owner_rep >= 0
        or frh.owner_id is null
      )
  and not (
        frh.was_closed_or_migrated = 1
        and frh.was_reopened = 0
      )
order by
    frh.heat_bucket desc,
    frh.rn_score asc,
    frh.q_score desc,
    frh.viewcount desc
limit 200;