with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.creationdate desc, u.id desc) as rn_recent
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_badge_stats as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
q_posts as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.closeddate,
    p.title,
    p.tags,
    coalesce(p.acceptedanswerid, 0) as acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
a_posts as (
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
user_post_activity as (
  select
    u.id as user_id,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end), 0) as questions,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end), 0) as answers,
    coalesce(sum(case when p.posttypeid = 1 then p.score else 0 end), 0) as q_score,
    coalesce(sum(case when p.posttypeid = 2 then p.score else 0 end), 0) as a_score,
    coalesce(sum(p.viewcount), 0) as total_views,
    coalesce(sum(p.commentcount), 0) as total_post_comments,
    min(p.creationdate) as first_post_date,
    max(p.creationdate) as last_post_date
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
user_comment_stats as (
  select
    u.id as user_id,
    coalesce(sum(c.score), 0) as comment_score_sum,
    coalesce(count(c.id), 0) as comment_count,
    max(c.creationdate) as last_comment_date
  from users u
  left join comments c on c.userid = u.id
  group by u.id
),
user_vote_stats as (
  select
    u.id as user_id,
    coalesce(sum(case when v.votetypeid = 2 then 1 else 0 end), 0) as upvotes_cast,
    coalesce(sum(case when v.votetypeid = 3 then 1 else 0 end), 0) as downvotes_cast,
    coalesce(sum(case when v.votetypeid = 5 then 1 else 0 end), 0) as favorites_cast,
    coalesce(sum(case when v.votetypeid = 8 then v.bountyamount else 0 end), 0) as bounty_started,
    coalesce(sum(case when v.votetypeid = 9 then v.bountyamount else 0 end), 0) as bounty_awarded
  from users u
  left join votes v on v.userid = u.id
  group by u.id
),
question_engagement as (
  select
    q.user_id,
    count(*) as questions_asked,
    sum(case when q.acceptedanswerid <> 0 then 1 else 0 end) as questions_with_accepted,
    avg(nullif(q.answercount, 0)) filter (where q.answercount is not null) as avg_answercount,
    avg(nullif(q.viewcount, 0)) filter (where q.viewcount is not null) as avg_views,
    percentile_cont(0.5) within group (order by coalesce(q.viewcount,0)) as p50_views,
    percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) as p90_views
  from q_posts q
  group by q.user_id
),
answer_accepts as (
  select
    a.user_id,
    count(*) filter (where a.id = q.acceptedanswerid) as accepted_answers,
    count(*) as total_answers
  from a_posts a
  left join q_posts q on q.id = a.question_id
  group by a.user_id
),
user_time_to_first_post as (
  select
    u.id as user_id,
    extract(epoch from (min(p.creationdate) - u.creationdate)) / 3600.0 as hours_to_first_post
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id, u.creationdate
),
post_linking as (
  select
    u.id as user_id,
    count(distinct pl.id) filter (where pl.linktypeid = 1) as linked_refs,
    count(distinct pl.id) filter (where pl.linktypeid = 3) as duplicate_links_out,
    count(distinct case when pl.linktypeid = 3 and pl.relatedpostid = q.id then pl.id end) as marked_as_duplicate_of_user_question
  from users u
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join postlinks pl on pl.postid = q.id
  group by u.id
),
closure_reasons as (
  select
    ph.postid,
    max(ph.creationdate) as last_close_date,
    cast(max(case
          when ph.posthistorytypeid = 10 then
            nullif(regexp_replace(coalesce(ph.comment, ''), '[^0-9]', '', 'g'), '')
        end) as integer) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid in (10, 35)
  group by ph.postid
),
close_reason_lookup as (
  select
    crt.id as close_reason_id,
    crt.name as close_reason_name
  from closereasontypes crt
),
user_closure_stats as (
  select
    u.id as user_id,
    count(*) filter (where q.closeddate is not null) as closed_questions,
    count(*) filter (where q.closeddate is null) as open_questions,
    count(*) filter (where cr.last_close_reason_id = 101) as closed_as_duplicate,
    count(*) filter (where cr.last_close_reason_id in (102,103,104,105)) as closed_other
  from users u
  left join posts q on q.owneruserid = u.id and q.posttypeid = 1
  left join closure_reasons cr on cr.postid = q.id
  group by u.id
),
user_quality_scores as (
  select
    u.id as user_id,
    case
      when upa.answers + upa.questions = 0 then null
      else round( (coalesce(upa.a_score,0) * 1.0 + coalesce(upa.q_score,0) * 0.5
          + coalesce(aas.accepted_answers,0) * 5.0
          - least(coalesce(ucs.downvotes_cast,0), 100) * 0.2
          + least(coalesce(ucs.upvotes_cast,0), 1000) * 0.05) / greatest(1, upa.answers + upa.questions), 3)
    end as quality_score
  from users u
  left join user_post_activity upa on upa.user_id = u.id
  left join answer_accepts aas on aas.user_id = u.id
  left join user_vote_stats ucs on ucs.user_id = u.id
),
stringy_bits as (
  select
    u.id as user_id,
    lower(coalesce(nullif(u.displayname,''),'anonymous')) as disp_lower,
    char_length(coalesce(u.displayname,'')) as disp_len,
    position(' ' in coalesce(u.displayname,'')) as first_space_pos,
    substring(coalesce(u.location,''), 1, 20) as loc_prefix,
    case when u.displayname is null or trim(u.displayname) = '' then 1 else 0 end as is_anon
  from users u
),
user_ranked as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    row_number() over (partition by ru.cohort_month order by uq.quality_score desc nulls last, ru.reputation desc, ru.user_id) as rank_in_cohort,
    dense_rank() over (order by uq.quality_score desc nulls last) as dense_rank_quality,
    ntile(10) over (order by coalesce(uq.quality_score,0)) as decile_quality
  from recent_users ru
  left join user_quality_scores uq on uq.user_id = ru.user_id
),
engagement_flags as (
  select
    u.id as user_id,
    case
      when coalesce(qe.questions_asked,0) >= 5 and coalesce(aas.total_answers,0) >= 10 then 'high'
      when coalesce(qe.questions_asked,0) + coalesce(aas.total_answers,0) >= 5 then 'medium'
      when coalesce(qe.questions_asked,0) + coalesce(aas.total_answers,0) >= 1 then 'low'
      else 'none'
    end as engagement_level,
    case
      when u.reputation >= 20000 then 'legend'
      when u.reputation >= 10000 then 'guru'
      when u.reputation >= 3000 then 'expert'
      when u.reputation >= 1000 then 'pro'
      when u.reputation >= 100 then 'novice'
      else 'newbie'
    end as rep_bucket
  from users u
  left join question_engagement qe on qe.user_id = u.id
  left join answer_accepts aas on aas.user_id = u.id
),
cohort_summary as (
  select
    ur.cohort_month,
    count(*) as users_in_cohort,
    avg(uq.quality_score) as avg_quality,
    percentile_cont(0.5) within group (order by uq.quality_score) as p50_quality
  from user_ranked ur
  left join user_quality_scores uq on uq.user_id = ur.user_id
  group by ur.cohort_month
),
final_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.websiteurl,
    ru.cohort_month,
    ub.total_badges,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    upa.questions,
    upa.answers,
    aas.accepted_answers,
    qe.questions_with_accepted,
    ucs.upvotes_cast,
    ucs.downvotes_cast,
    ucs.favorites_cast,
    ucs.bounty_started,
    ucs.bounty_awarded,
    qcs.closed_questions,
    qcs.open_questions,
    qcs.closed_as_duplicate,
    qcs.closed_other,
    ucs2.comment_score_sum,
    ucs2.comment_count,
    pl.linked_refs,
    pl.duplicate_links_out,
    pl.marked_as_duplicate_of_user_question,
    utfp.hours_to_first_post,
    uq.quality_score,
    ur.rank_in_cohort,
    ur.decile_quality,
    ef.engagement_level,
    ef.rep_bucket,
    sb.disp_lower,
    sb.disp_len,
    sb.first_space_pos,
    sb.loc_prefix,
    sb.is_anon
  from recent_users ru
  left join user_badge_stats ub on ub.userid = ru.user_id
  left join user_post_activity upa on upa.user_id = ru.user_id
  left join answer_accepts aas on aas.user_id = ru.user_id
  left join question_engagement qe on qe.user_id = ru.user_id
  left join user_vote_stats ucs on ucs.user_id = ru.user_id
  left join user_comment_stats ucs2 on ucs2.user_id = ru.user_id
  left join post_linking pl on pl.user_id = ru.user_id
  left join user_time_to_first_post utfp on utfp.user_id = ru.user_id
  left join user_quality_scores uq on uq.user_id = ru.user_id
  left join user_ranked ur on ur.user_id = ru.user_id
  left join user_closure_stats qcs on qcs.user_id = ru.user_id
  left join engagement_flags ef on ef.user_id = ru.user_id
  left join stringy_bits sb on sb.user_id = ru.user_id
),
flagged_users as (
  select
    fu.*,
    case
      when coalesce(fu.answers,0) = 0 and coalesce(fu.questions,0) = 0 then 'no_posts'
      when coalesce(fu.accepted_answers,0) >= 5 and coalesce(fu.quality_score,0) > 10 then 'top_answerer'
      when coalesce(fu.closed_as_duplicate,0) >= 3 then 'dupe_magnet'
      when coalesce(fu.downvotes_cast,0) > coalesce(fu.upvotes_cast,0) then 'grumpy'
      when fu.is_anon = 1 and fu.reputation < 100 then 'lurker'
      else 'regular'
    end as persona
  from final_users fu
),
cohort_aggregate as (
  select
    fu.cohort_month,
    count(*) filter (where fu.persona = 'top_answerer') as top_answerers,
    count(*) filter (where fu.persona = 'dupe_magnet') as dupe_magnets,
    count(*) filter (where fu.persona = 'grumpy') as grumpies,
    count(*) filter (where fu.persona = 'lurker') as lurkers
  from flagged_users fu
  group by fu.cohort_month
)
select
  fu.user_id,
  fu.displayname,
  fu.reputation,
  fu.rep_bucket,
  fu.engagement_level,
  fu.persona,
  fu.cohort_month,
  cs.users_in_cohort,
  ca.top_answerers,
  ca.dupe_magnets,
  ca.grumpies,
  ca.lurkers,
  fu.total_badges,
  fu.gold_badges,
  fu.silver_badges,
  fu.bronze_badges,
  fu.questions,
  fu.answers,
  fu.accepted_answers,
  fu.questions_with_accepted,
  fu.upvotes_cast,
  fu.downvotes_cast,
  fu.favorites_cast,
  fu.bounty_started,
  fu.bounty_awarded,
  fu.closed_questions,
  fu.open_questions,
  fu.closed_as_duplicate,
  fu.closed_other,
  fu.comment_score_sum,
  fu.comment_count,
  fu.linked_refs,
  fu.duplicate_links_out,
  fu.marked_as_duplicate_of_user_question,
  fu.hours_to_first_post,
  fu.quality_score,
  fu.rank_in_cohort,
  fu.decile_quality,
  fu.location,
  fu.websiteurl,
  fu.disp_lower,
  fu.disp_len,
  fu.first_space_pos,
  fu.loc_prefix
from flagged_users fu
left join cohort_summary cs on cs.cohort_month = fu.cohort_month
left join cohort_aggregate ca on ca.cohort_month = fu.cohort_month
where
  (fu.quality_score is not null and fu.rank_in_cohort <= 50)
  or (fu.persona in ('top_answerer','dupe_magnet'))
order by fu.cohort_month desc nulls last, fu.rank_in_cohort nulls last, fu.quality_score desc nulls last, fu.reputation desc, fu.user_id
limit 500;