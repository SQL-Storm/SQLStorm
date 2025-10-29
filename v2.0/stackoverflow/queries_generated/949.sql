-- {"query": "949.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3329} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
    date_trunc('month', u.creationdate) as cohort_month,
    ntile(10) over (order by u.reputation desc, u.id) as rep_decile
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
q_and_a as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer
  from posts p
  where p.posttypeid in (1,2)
),
votes_by_post as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at,
    count(*) as total_votes
  from votes v
  group by v.postid
),
post_close_info as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    max(case when ph.posthistorytypeid = 10 then nullif(ph.comment,'') end) as last_close_reason_raw
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as dup_link_count,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    min(pl.creationdate) as first_linked_at
  from postlinks pl
  group by pl.postid
),
badges_ranked as (
  select
    b.userid,
    b.name,
    b.class,
    b.date,
    row_number() over (partition by b.userid order by b.class asc, b.date asc, b.id asc) as rn_first,
    row_number() over (partition by b.userid order by b.class desc, b.date desc, b.id desc) as rn_last
  from badges b
),
user_badge_summary as (
  select
    u.id as user_id,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at,
    max(b.name) filter (where br.rn_first = 1) as first_badge_name,
    max(b.name) filter (where br.rn_last = 1) as last_badge_name
  from users u
  left join badges b on b.userid = u.id
  left join badges_ranked br on br.userid = b.userid and br.name = b.name and br.date = b.date and br.class = b.class
  group by u.id
),
comment_activity as (
  select
    c.userid,
    count(*) as comments_made,
    max(c.creationdate) as last_comment_at,
    avg(c.score) filter (where c.score is not null) as avg_comment_score,
    sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_comments
  from comments c
  group by c.userid
),
owner_activity as (
  select
    qa.owneruserid as user_id,
    count(*) filter (where qa.is_question = 1) as questions,
    count(*) filter (where qa.is_answer = 1) as answers,
    coalesce(sum(qa.score),0) as total_post_score,
    sum(coalesce(vbp.upvotes,0)) as upvotes_rcvd,
    sum(coalesce(vbp.downvotes,0)) as downvotes_rcvd,
    sum(coalesce(vbp.total_votes,0)) as total_votes_rcvd,
    max(qa.creationdate) as last_post_at,
    min(qa.creationdate) as first_post_at,
    sum(case when qa.is_question = 1 and qa.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
    sum(case when qa.is_answer = 1 and qa.id = (select p.acceptedanswerid from posts p where p.id = qa.parentid) then 1 else 0 end) as accepted_answers_given
  from q_and_a qa
  left join votes_by_post vbp on vbp.postid = qa.id
  group by qa.owneruserid
),
question_metrics as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as asked_at,
    q.score as q_score,
    q.viewcount as q_views,
    q.tags,
    v.upvotes as q_upvotes,
    v.downvotes as q_downvotes,
    v.total_votes as q_total_votes,
    pc.first_closed_at,
    pc.last_reopened_at,
    pc.close_events,
    dl.dup_link_count,
    dl.linked_count,
    case
      when q.acceptedanswerid is not null then
        (select a.owneruserid from posts a where a.id = q.acceptedanswerid)
      else null
    end as accepted_answerer_id,
    (select count(*) from posts a where a.parentid = q.id and a.posttypeid = 2) as answers_count
  from q_and_a q
  left join votes_by_post v on v.postid = q.id
  left join post_close_info pc on pc.postid = q.id
  left join dup_links dl on dl.postid = q.id
  where q.is_question = 1
),
tag_explode as (
  select
    qm.question_id,
    unnest(string_to_array(substring(qm.tags, 2, greatest(length(qm.tags)-2,0)), '><')) as tagname
  from question_metrics qm
  where qm.tags is not null and qm.tags like '<%>'
),
top_tags as (
  select
    t.tagname,
    count(*) as freq
  from tag_explode t
  group by t.tagname
  having count(*) >= (
    select percentile_disc(0.9) within group (order by cnt)
    from (
      select tagname, count(*) as cnt
      from tag_explode
      group by tagname
    ) s
  )
),
user_joined_top_tags as (
  select
    qm.asker_id as user_id,
    count(distinct tt.tagname) as distinct_top_tags_asked_in
  from question_metrics qm
  join tag_explode te on te.question_id = qm.question_id
  join top_tags tt on tt.tagname = te.tagname
  group by qm.asker_id
),
activity_calendar as (
  select
    u.id as user_id,
    date_trunc('day', p.creationdate) as day,
    count(*) as posts_that_day
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, date_trunc('day', p.creationdate)
),
activity_gaps as (
  select
    user_id,
    max(day) as last_active_day,
    min(day) as first_active_day,
    max(day) - min(day) as span_days,
    max(posts_that_day) as max_posts_in_a_day
  from activity_calendar
  group by user_id
),
user_quality_score as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.rep_decile,
    oa.questions,
    oa.answers,
    oa.total_post_score,
    oa.upvotes_rcvd,
    oa.downvotes_rcvd,
    oa.total_votes_rcvd,
    oa.questions_with_accepted,
    oa.accepted_answers_given,
    ubs.total_badges,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges,
    ca.comments_made,
    ca.avg_comment_score,
    ca.thanks_comments,
    ag.span_days,
    ag.max_posts_in_a_day,
    ujt.distinct_top_tags_asked_in,
    coalesce(oa.upvotes_rcvd - oa.downvotes_rcvd,0) as net_votes_rcvd,
    case
      when coalesce(oa.answers,0) = 0 then null
      else round(100.0 * coalesce(oa.accepted_answers_given,0) / nullif(oa.answers,0), 2)
    end as accept_rate_pct,
    case
      when coalesce(oa.questions,0) = 0 then null
      else round(100.0 * coalesce(oa.questions_with_accepted,0) / nullif(oa.questions,0), 2)
    end as q_with_accept_pct,
    round(
      coalesce(oa.total_post_score,0) * 0.4
      + coalesce(oa.upvotes_rcvd,0) * 0.3
      - coalesce(oa.downvotes_rcvd,0) * 0.2
      + coalesce(ubs.gold_badges,0) * 8
      + coalesce(ubs.silver_badges,0) * 3
      + coalesce(ubs.bronze_badges,0) * 1
      + coalesce(ca.avg_comment_score,0) * 2
      + coalesce(ujt.distinct_top_tags_asked_in,0) * 1.5
      + least(coalesce(ag.max_posts_in_a_day,0), 10) * 0.5
    , 2) as quality_score
  from recent_users ru
  left join owner_activity oa on oa.user_id = ru.user_id
  left join user_badge_summary ubs on ubs.user_id = ru.user_id
  left join comment_activity ca on ca.userid = ru.user_id
  left join activity_gaps ag on ag.user_id = ru.user_id
  left join user_joined_top_tags ujt on ujt.user_id = ru.user_id
),
user_vs_cohort as (
  select
    uqs.*,
    avg(quality_score) over (partition by cohort_month) as cohort_avg_qs,
    percentile_cont(0.5) within group (order by quality_score) over (partition by cohort_month) as cohort_median_qs,
    rank() over (partition by cohort_month order by quality_score desc nulls last) as cohort_rank
  from user_quality_score uqs
),
question_outliers as (
  select
    qm.question_id,
    qm.asker_id,
    qm.q_views,
    qm.q_score,
    qm.q_total_votes,
    avg(qm.q_views) over () as avg_views_all,
    stddev_pop(qm.q_views) over () as std_views_all
  from question_metrics qm
),
highly_viewed_questions as (
  select
    qo.question_id,
    qo.asker_id,
    qo.q_views
  from question_outliers qo
  where qo.std_views_all > 0
    and qo.q_views >= qo.avg_views_all + 2 * qo.std_views_all
),
final_users as (
  select
    uvc.user_id,
    uvc.displayname,
    uvc.reputation,
    uvc.cohort_month,
    uvc.rep_decile,
    uvc.quality_score,
    uvc.cohort_avg_qs,
    uvc.cohort_median_qs,
    uvc.cohort_rank,
    coalesce(hv.hv_count, 0) as highly_viewed_questions
  from user_vs_cohort uvc
  left join (
    select asker_id, count(*) as hv_count
    from highly_viewed_questions
    group by asker_id
  ) hv on hv.asker_id = uvc.user_id
),
top_users as (
  select
    fu.*,
    dense_rank() over (order by fu.quality_score desc nulls last, fu.reputation desc, fu.user_id) as global_rank
  from final_users fu
),
tag_leaders as (
  select
    te.tagname,
    a.owneruserid as answerer_id,
    count(*) as answers_in_tag,
    sum(a.score) as total_answer_score,
    avg(a.score) as avg_answer_score,
    row_number() over (partition by te.tagname order by sum(a.score) desc, count(*) desc, a.owneruserid) as rn
  from tag_explode te
  join posts a on a.parentid = te.question_id and a.posttypeid = 2
  group by te.tagname, a.owneruserid
),
top_tag_leaders as (
  select tl.*
  from tag_leaders tl
  where tl.rn <= 3
)
select
  tu.global_rank,
  tu.user_id,
  tu.displayname,
  tu.reputation,
  tu.cohort_month,
  tu.rep_decile,
  tu.quality_score,
  tu.cohort_avg_qs,
  tu.cohort_median_qs,
  tu.cohort_rank,
  tu.highly_viewed_questions,
  coalesce(json_agg(json_build_object(
    'tag', ttl.tagname,
    'answerer_id', ttl.answerer_id,
    'answers_in_tag', ttl.answers_in_tag,
    'total_answer_score', ttl.total_answer_score,
    'avg_answer_score', ttl.avg_answer_score
  ) order by ttl.tagname) filter (where ttl.tagname is not null), '[]'::json) as top_tags_contributed
from top_users tu
left join top_tag_leaders ttl on ttl.answerer_id = tu.user_id
where tu.global_rank <= 200
group by
  tu.global_rank, tu.user_id, tu.displayname, tu.reputation, tu.cohort_month, tu.rep_decile,
  tu.quality_score, tu.cohort_avg_qs, tu.cohort_median_qs, tu.cohort_rank, tu.highly_viewed_questions
order by tu.global_rank, tu.user_id;