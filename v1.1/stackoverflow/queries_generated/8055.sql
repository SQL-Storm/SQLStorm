-- {"query": "8055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3514} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.closeddate,
    p.communityowneddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.commentcount
  from posts p
  where p.posttypeid = 2
),
q_activity as (
  select
    q.id as question_id,
    q.user_id,
    q.creationdate,
    q.score,
    q.viewcount,
    q.answercount,
    q.favoritecount,
    q.commentcount,
    q.closeddate,
    q.communityowneddate,
    /* extract first tag and tag count */
    nullif(split_part(trim(both '<>' from coalesce(q.tags, '')), '><', 1), '') as first_tag,
    case when q.tags is null then 0
         when length(q.tags) <= 2 then 0
         else cardinality(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))
    end as tag_count
  from question_posts q
),
a_stats as (
  select
    a.question_id,
    count(*) as answers_count,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
    avg(a.score::numeric) as avg_answer_score,
    min(a.creationdate) as first_answer_at,
    max(a.creationdate) as last_answer_at
  from answer_posts a
  group by a.question_id
),
v_summary as (
  select
    v.postid as post_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  where v.creationdate >= (select min(creationdate) from q_activity)
  group by v.postid
),
ph_close as (
  select
    ph.postid as post_id,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (10,35)) as first_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (11)) as last_reopened_at,
    max((ph.comment)::int) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10,11,35)
  group by ph.postid
),
link_dupes as (
  select
    pl.postid as post_id,
    count(*) filter (where pl.linktypeid = 3) as dup_mark_count,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  group by pl.postid
),
tag_info as (
  select
    t.tagname,
    t.count as tag_total_count,
    coalesce(t.ismoderatoronly, 0) as is_moderator_only,
    coalesce(t.isrequired, 0) as is_required
  from tags t
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
user_comment_stats as (
  select
    c.userid as user_id,
    count(*) as total_comments,
    avg(c.score::numeric) as avg_comment_score,
    max(c.creationdate) as last_comment_at,
    sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as gratitude_comments
  from comments c
  where c.userid is not null
  group by c.userid
),
q_enriched as (
  select
    qa.*,
    coalesce(vs.upvotes, 0) as q_upvotes,
    coalesce(vs.downvotes, 0) as q_downvotes,
    coalesce(vs.favorites, 0) as q_favorites,
    coalesce(vs.bounty_started, 0) as bounty_started,
    coalesce(vs.bounty_awarded, 0) as bounty_awarded,
    coalesce(as2.answers_count, 0) as answers_count_actual,
    as2.positive_answers,
    as2.avg_answer_score,
    as2.first_answer_at,
    as2.last_answer_at,
    ph.first_closed_at,
    ph.last_reopened_at,
    ph.last_close_reason_id,
    ld.dup_mark_count,
    ld.linked_count,
    ld.last_link_at
  from q_activity qa
  left join v_summary vs on vs.post_id = qa.question_id
  left join a_stats as2 on as2.question_id = qa.question_id
  left join ph_close ph on ph.post_id = qa.question_id
  left join link_dupes ld on ld.post_id = qa.question_id
),
user_engagement as (
  select
    ru.user_id,
    count(*) filter (where qe.creationdate >= ru.creationdate) as questions_total,
    sum(case when qe.score >= 5 then 1 else 0 end) as questions_popular,
    sum(coalesce(qe.q_upvotes,0)) as total_upvotes_on_questions,
    sum(coalesce(qe.q_downvotes,0)) as total_downvotes_on_questions,
    sum(case when qe.first_answer_at is not null and qe.first_answer_at <= qe.creationdate + interval '1 day' then 1 else 0 end) as questions_answered_within_1d,
    sum(case when qe.dup_mark_count > 0 then 1 else 0 end) as questions_marked_duplicate,
    max(qe.creationdate) as last_question_at
  from recent_users ru
  left join q_enriched qe on qe.user_id = ru.user_id
  group by ru.user_id
),
answerer_activity as (
  select
    ru.user_id,
    count(a.id) as answers_total,
    sum(case when a.score >= 1 then 1 else 0 end) as answers_positive,
    sum(a.score) as answers_score_sum,
    min(a.creationdate) as first_answer_at,
    max(a.creationdate) as last_answer_at
  from recent_users ru
  left join answer_posts a on a.user_id = ru.user_id
  group by ru.user_id
),
quality_scores as (
  select
    ru.user_id,
    /* compute a composite engagement/quality score */
    (
      0.4 * coalesce(ue.questions_popular, 0)
      + 0.3 * coalesce(aa.answers_positive, 0)
      + 0.2 * coalesce(ub.gold_badges, 0)
      + 0.1 * greatest(coalesce(ue.total_upvotes_on_questions,0) - coalesce(ue.total_downvotes_on_questions,0), 0)
    )::numeric as contribution_score,
    case
      when coalesce(aa.answers_total,0) + coalesce(ue.questions_total,0) = 0 then null
      else round(
        (
          coalesce(aa.answers_score_sum::numeric,0)
          + coalesce(ue.total_upvotes_on_questions::numeric,0)
          - coalesce(ue.total_downvotes_on_questions::numeric,0)
        ) / nullif(coalesce(aa.answers_total,0) + coalesce(ue.questions_total,0), 0)
      , 3)
    end as avg_score_per_post
  from recent_users ru
  left join user_engagement ue on ue.user_id = ru.user_id
  left join answerer_activity aa on aa.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
),
tag_ranks as (
  select
    qe.first_tag,
    count(*) as q_count,
    sum(qe.q_upvotes) as upvotes_sum,
    sum(qe.q_downvotes) as downvotes_sum,
    rank() over (order by count(*) desc, sum(qe.q_upvotes) desc) as tag_rank_by_volume
  from q_enriched qe
  where qe.first_tag is not null
  group by qe.first_tag
),
user_top_tag as (
  select
    qe.user_id,
    qe.first_tag,
    count(*) as cnt,
    row_number() over (partition by qe.user_id order by count(*) desc, sum(qe.q_upvotes) desc, min(qe.creationdate)) as rn
  from q_enriched qe
  where qe.first_tag is not null
  group by qe.user_id, qe.first_tag
),
cohorts as (
  select
    cohort_month,
    count(*) as users_in_cohort,
    percentile_disc(0.5) within group (order by reputation) as cohort_median_rep
  from recent_users
  group by cohort_month
),
final_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.cohort_month,
    ru.location,
    ru.websiteurl_norm,
    ue.questions_total,
    ue.questions_popular,
    ue.questions_answered_within_1d,
    ue.questions_marked_duplicate,
    ue.total_upvotes_on_questions,
    ue.total_downvotes_on_questions,
    ue.last_question_at,
    aa.answers_total,
    aa.answers_positive,
    aa.answers_score_sum,
    aa.first_answer_at,
    aa.last_answer_at as user_last_answer_at,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    ub.last_badge_at,
    ucs.total_comments,
    ucs.avg_comment_score,
    ucs.last_comment_at,
    ucs.gratitude_comments,
    qs.contribution_score,
    qs.avg_score_per_post,
    utt.first_tag as top_tag,
    tr.tag_rank_by_volume,
    co.cohort_median_rep
  from recent_users ru
  left join user_engagement ue on ue.user_id = ru.user_id
  left join answerer_activity aa on aa.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join user_comment_stats ucs on ucs.user_id = ru.user_id
  left join quality_scores qs on qs.user_id = ru.user_id
  left join lateral (
    select first_tag from user_top_tag ut where ut.user_id = ru.user_id and ut.rn = 1
  ) utt on true
  left join tag_ranks tr on tr.first_tag = utt.first_tag
  left join cohorts co on co.cohort_month = ru.cohort_month
),
outlier_detection as (
  select
    fu.*,
    /* z-scores for reputation and contribution */
    (fu.reputation - avg(fu.reputation) over ()) / nullif(stddev_pop(fu.reputation) over (),0) as rep_z,
    (coalesce(fu.contribution_score,0) - avg(coalesce(fu.contribution_score,0)) over ()) / nullif(stddev_pop(coalesce(fu.contribution_score,0)) over (),0) as contrib_z
  from final_users fu
),
ranked as (
  select
    od.*,
    dense_rank() over (order by coalesce(od.contribution_score, -1e9) desc, od.reputation desc, od.user_id) as overall_rank,
    row_number() over (partition by od.cohort_month order by coalesce(od.contribution_score, -1e9) desc, od.reputation desc) as cohort_rank
  from outlier_detection od
)
select
  r.user_id,
  r.displayname,
  r.location,
  r.websiteurl_norm,
  r.cohort_month,
  r.reputation,
  r.rep_z,
  r.contribution_score,
  r.contrib_z,
  r.avg_score_per_post,
  r.questions_total,
  r.questions_popular,
  r.questions_answered_within_1d,
  r.questions_marked_duplicate,
  r.total_upvotes_on_questions,
  r.total_downvotes_on_questions,
  r.answers_total,
  r.answers_positive,
  r.answers_score_sum,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.total_comments,
  r.avg_comment_score,
  r.gratitude_comments,
  r.top_tag,
  r.tag_rank_by_volume,
  r.cohort_median_rep,
  r.overall_rank,
  r.cohort_rank,
  /* complicated predicate-driven label */
  case
    when r.contribution_score is null then 'new/idle'
    when r.contrib_z >= 2 and r.rep_z >= 1 then 'elite'
    when r.contrib_z >= 1 then 'high'
    when r.contrib_z <= -1 and r.rep_z <= -1 then 'at-risk'
    else 'normal'
  end as segment_label,
  /* correlated subquery: most engaged question title by this user in last 90 days */
  (
    select q2.title
    from q_enriched q2
    where q2.user_id = r.user_id
      and q2.creationdate >= now() - interval '90 days'
    order by (coalesce(q2.q_upvotes,0) - coalesce(q2.q_downvotes,0)) desc, q2.viewcount desc, q2.creationdate desc
    limit 1
  ) as best_recent_question_title,
  /* string expression combining tag info */
  case
    when r.top_tag is null then 'no tag focus'
    else concat_ws(' | ',
      r.top_tag,
      concat('rank#', coalesce(r.tag_rank_by_volume::text, 'n/a')),
      case when exists (select 1 from tag_info ti where ti.tagname = r.top_tag and ti.is_moderator_only = 1) then 'mod-only' else 'open' end
    )
  end as tag_profile
from ranked r
where
  /* set operator style filter via union of ids that meet complex conditions */
  r.user_id in (
    select user_id from final_users where coalesce(contribution_score,0) > 0
    union
    select user_id from final_users where reputation > (select avg(reputation) from final_users)
    except
    select user_id from final_users where coalesce(answers_total,0) = 0 and coalesce(questions_total,0) = 0
  )
  and (
    /* complicated boolean logic and NULL handling */
    (r.questions_total is not null and r.questions_total >= 1)
    or (r.answers_total is not null and r.answers_total >= 5)
    or (r.contribution_score is not null and r.contribution_score >= 10)
  )
order by r.overall_rank, r.user_id
limit 500;