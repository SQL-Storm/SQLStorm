-- {"query": "300.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3547}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score,0)) as post_score,
    sum(coalesce(p.viewcount,0)) as views,
    max(p.lastactivitydate) as last_post_activity,
    sum(coalesce(p.commentcount,0)) as comment_count,
    count(distinct p.id) filter (where p.posttypeid = 1 and p.answercount > 0) as answered_questions
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    bool_or(b.tagbased = true) as has_tag_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_tag_expansion as (
  select
    p.id as question_id,
    lower(trim(t.tag)) as tag
  from posts p
  cross join lateral (
    select unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
  ) t
  where p.posttypeid = 1
),
user_top_tags as (
  select
    p.owneruserid as user_id,
    qte.tag,
    count(*) as tag_posts,
    row_number() over (partition by p.owneruserid order by count(*) desc, min(p.creationdate)) as rn
  from posts p
  join question_tag_expansion qte
    on qte.question_id = p.id
  where p.owneruserid is not null
  group by p.owneruserid, qte.tag
),
user_votes as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid in (8,9)) as bounties_involved,
    sum(coalesce(v.bountyamount,0)) as total_bounty_amount,
    min(v.creationdate) as first_vote_date,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
question_closures as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    count(*) as close_events
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
duplicate_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_refs,
    count(*) filter (where pl.linktypeid = 1) as linked_refs,
    max(pl.creationdate) as last_link_date
  from postlinks pl
  group by pl.postid
),
accepted_answers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers_count,
    sum(coalesce(a.score,0)) as accepted_answers_score
  from posts q
  join posts a
    on a.id = q.acceptedanswerid
  where q.posttypeid = 1
  group by a.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as total_comments,
    sum(c.score) as comment_score,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
post_edit_stats as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_made,
    count(*) filter (where ph.posthistorytypeid = 24) as suggested_edits_applied,
    max(ph.creationdate) as last_edit_date
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
user_recent_activity_score as (
  select
    ua.user_id,
    (
      coalesce(ua.q_count,0) * 3
      + coalesce(ua.a_count,0) * 5
      + coalesce(ua.post_score,0)
      + coalesce(uv.upvotes_cast,0) * 0.5
      - coalesce(uv.downvotes_cast,0) * 0.25
      + least(coalesce(ba.total_badges,0), 50) * 0.8
      + coalesce(cs.comment_score,0) * 0.2
      + coalesce(pa.edits_made,0) * 0.3
      + coalesce(ac.accepted_answers_count,0) * 8
    ) as activity_points
  from user_activity ua
  left join user_votes uv on uv.user_id = ua.user_id
  left join user_badges ba on ba.user_id = ua.user_id
  left join comment_stats cs on cs.user_id = ua.user_id
  left join post_edit_stats pa on pa.user_id = ua.user_id
  left join accepted_answers ac on ac.user_id = ua.user_id
),
question_metrics as (
  select
    q.owneruserid as user_id,
    count(*) as total_questions,
    avg(nullif(q.viewcount,0)) as avg_question_views_nonzero,
    avg(q.score) as avg_question_score,
    count(*) filter (where q.closeddate is not null) as closed_questions,
    count(*) filter (where q.answercount > 0) as questions_with_answers,
    count(distinct q.id) filter (where d.duplicate_refs > 0) as questions_marked_duplicate,
    sum(coalesce(d.duplicate_refs,0)) as total_duplicate_refs
  from posts q
  left join duplicate_links d on d.postid = q.id
  where q.posttypeid = 1
  group by q.owneruserid
),
answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as total_answers,
    avg(a.score) as avg_answer_score,
    sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as accepted_answers_given,
    percentile_cont(0.5) within group (order by a.score) as median_answer_score
  from posts a
  left join posts q on q.id = a.parentid and a.posttypeid = 2
  where a.posttypeid = 2
  group by a.owneruserid
),
user_ranked as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate,
    ru.location,
    ru.websiteurl,
    ru.cohort_month,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.post_score,0) as post_score,
    coalesce(ua.views,0) as views,
    ua.last_post_activity,
    coalesce(ba.total_badges,0) as total_badges,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    ba.has_tag_badges,
    ba.last_badge_date,
    coalesce(uv.upvotes_cast,0) as upvotes_cast,
    coalesce(uv.downvotes_cast,0) as downvotes_cast,
    coalesce(uv.bounties_involved,0) as bounties_involved,
    coalesce(uv.total_bounty_amount,0) as total_bounty_amount,
    uv.first_vote_date,
    uv.last_vote_date,
    coalesce(cs.total_comments,0) as total_comments,
    coalesce(cs.comment_score,0) as comment_score,
    cs.avg_comment_score,
    cs.last_comment_date,
    coalesce(pe.edits_made,0) as edits_made,
    coalesce(pe.suggested_edits_applied,0) as suggested_edits_applied,
    pe.last_edit_date,
    coalesce(qm.total_questions,0) as total_questions,
    qm.avg_question_views_nonzero,
    qm.avg_question_score,
    coalesce(qm.closed_questions,0) as closed_questions,
    coalesce(qm.questions_with_answers,0) as questions_with_answers,
    coalesce(qm.questions_marked_duplicate,0) as questions_marked_duplicate,
    coalesce(qm.total_duplicate_refs,0) as total_duplicate_refs,
    coalesce(am.total_answers,0) as total_answers,
    am.avg_answer_score,
    coalesce(am.accepted_answers_given,0) as accepted_answers_given,
    am.median_answer_score,
    coalesce(ac.accepted_answers_count,0) as accepted_answers_count,
    coalesce(ac.accepted_answers_score,0) as accepted_answers_score,
    utt.tag as top_tag,
    utt.tag_posts as top_tag_posts,
    urs.activity_points
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_badges ba on ba.user_id = ru.user_id
  left join user_votes uv on uv.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join post_edit_stats pe on pe.user_id = ru.user_id
  left join question_metrics qm on qm.user_id = ru.user_id
  left join answer_metrics am on am.user_id = ru.user_id
  left join accepted_answers ac on ac.user_id = ru.user_id
  left join user_recent_activity_score urs on urs.user_id = ru.user_id
  left join lateral (
    select tag, tag_posts
    from user_top_tags utt
    where utt.user_id = ru.user_id and utt.rn = 1
  ) utt on true
),
post_outliers as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.posttypeid,
    p.score,
    p.viewcount,
    case
      when p.viewcount is null then null
      when p.viewcount = 0 then null
      else cast(p.score as numeric) / nullif(p.viewcount,0)
    end as score_per_view,
    rank() over (partition by p.owneruserid order by p.score desc nulls last) as score_rank_desc,
    rank() over (partition by p.owneruserid order by p.viewcount desc nulls last) as views_rank_desc
  from posts p
  where p.owneruserid is not null
),
best_post as (
  select
    po.user_id,
    po.post_id as best_post_id,
    po.posttypeid as best_post_type,
    po.score as best_post_score,
    po.viewcount as best_post_views,
    po.score_per_view as best_post_spv
  from post_outliers po
  where po.score_rank_desc = 1
),
most_viewed_post as (
  select
    po.user_id,
    po.post_id as most_viewed_post_id,
    po.posttypeid as most_viewed_post_type,
    po.score as most_viewed_post_score,
    po.viewcount as most_viewed_post_views,
    po.score_per_view as most_viewed_post_spv
  from post_outliers po
  where po.views_rank_desc = 1
),
cohort_stats as (
  select
    cohort_month,
    count(*) as users_in_cohort,
    percentile_cont(0.5) within group (order by reputation) as cohort_median_rep,
    avg(reputation) as cohort_avg_rep,
    avg(views) as cohort_avg_views,
    avg(activity_points) as cohort_avg_activity
  from user_ranked
  group by cohort_month
),
final_rank as (
  select
    ur.user_id,
    ur.displayname,
    ur.reputation,
    ur.creationdate,
    ur.location,
    ur.websiteurl,
    ur.cohort_month,
    ur.q_count,
    ur.a_count,
    ur.post_score,
    ur.views,
    ur.last_post_activity,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.has_tag_badges,
    ur.last_badge_date,
    ur.upvotes_cast,
    ur.downvotes_cast,
    ur.bounties_involved,
    ur.total_bounty_amount,
    ur.first_vote_date,
    ur.last_vote_date,
    ur.total_comments,
    ur.comment_score,
    ur.avg_comment_score,
    ur.last_comment_date,
    ur.edits_made,
    ur.suggested_edits_applied,
    ur.last_edit_date,
    ur.total_questions,
    ur.avg_question_views_nonzero,
    ur.avg_question_score,
    ur.closed_questions,
    ur.questions_with_answers,
    ur.questions_marked_duplicate,
    ur.total_duplicate_refs,
    ur.total_answers,
    ur.avg_answer_score,
    ur.accepted_answers_given,
    ur.median_answer_score,
    ur.accepted_answers_count,
    ur.accepted_answers_score,
    ur.top_tag,
    ur.top_tag_posts,
    ur.activity_points,
    bp.best_post_id,
    bp.best_post_type,
    bp.best_post_score,
    bp.best_post_views,
    bp.best_post_spv,
    mvp.most_viewed_post_id,
    mvp.most_viewed_post_type,
    mvp.most_viewed_post_score,
    mvp.most_viewed_post_views,
    mvp.most_viewed_post_spv,
    cs.users_in_cohort,
    cs.cohort_median_rep,
    cs.cohort_avg_rep,
    cs.cohort_avg_views,
    cs.cohort_avg_activity,
    row_number() over (
      partition by ur.cohort_month
      order by
        ur.activity_points desc nulls last,
        ur.reputation desc,
        coalesce(ur.post_score,0) desc,
        coalesce(ur.views,0) desc
    ) as cohort_rank,
    dense_rank() over (
      order by
        ur.activity_points desc nulls last,
        ur.reputation desc,
        coalesce(ur.post_score,0) desc
    ) as global_dense_rank
  from user_ranked ur
  left join best_post bp on bp.user_id = ur.user_id
  left join most_viewed_post mvp on mvp.user_id = ur.user_id
  left join cohort_stats cs on cs.cohort_month = ur.cohort_month
)
select
  fr.global_dense_rank,
  fr.cohort_rank,
  fr.cohort_month,
  fr.user_id,
  fr.displayname,
  fr.location,
  fr.websiteurl,
  fr.reputation,
  fr.activity_points,
  fr.q_count,
  fr.a_count,
  fr.total_questions,
  fr.total_answers,
  fr.accepted_answers_given,
  fr.accepted_answers_count,
  fr.post_score,
  fr.views,
  fr.avg_question_views_nonzero,
  fr.avg_question_score,
  fr.avg_answer_score,
  fr.median_answer_score,
  fr.closed_questions,
  fr.questions_with_answers,
  fr.questions_marked_duplicate,
  fr.total_duplicate_refs,
  fr.total_badges,
  fr.gold_badges,
  fr.silver_badges,
  fr.bronze_badges,
  fr.has_tag_badges,
  fr.top_tag,
  fr.top_tag_posts,
  fr.upvotes_cast,
  fr.downvotes_cast,
  fr.bounties_involved,
  fr.total_bounty_amount,
  fr.total_comments,
  fr.comment_score,
  fr.avg_comment_score,
  fr.edits_made,
  fr.suggested_edits_applied,
  fr.last_post_activity,
  fr.last_badge_date,
  fr.first_vote_date,
  fr.last_vote_date,
  fr.last_comment_date,
  fr.last_edit_date,
  fr.best_post_id,
  fr.best_post_type,
  fr.best_post_score,
  fr.best_post_views,
  fr.best_post_spv,
  fr.most_viewed_post_id,
  fr.most_viewed_post_type,
  fr.most_viewed_post_score,
  fr.most_viewed_post_views,
  fr.most_viewed_post_spv,
  fr.users_in_cohort,
  fr.cohort_median_rep,
  fr.cohort_avg_rep,
  fr.cohort_avg_views,
  fr.cohort_avg_activity
from final_rank fr
where (
    fr.activity_points > coalesce(fr.cohort_avg_activity, 0)
    or fr.reputation > coalesce(fr.cohort_median_rep, 0)
    or (fr.total_answers + fr.total_questions) > 0
  )
and (
    fr.top_tag is null
    or not (
      fr.top_tag like 'meta%' or fr.top_tag like 'discussion%' or fr.top_tag like 'off-topic%'
    )
  )
and (
    fr.websiteurl = 'n/a'
    or position('.' in fr.websiteurl) > 0
  )
order by fr.global_dense_rank, fr.cohort_rank
limit 250;