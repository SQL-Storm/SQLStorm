with
active_users as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.displayname), ''), '(anonymous)') as display_name,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.upvotes,
    u.downvotes,
    dense_rank() over (order by u.reputation desc, u.id) as rep_dr,
    u.id as _tmp_id_for_p90,
    ntile(20) over (order by u.reputation desc) as rep_ventile
  from users u
  where u.creationdate is not null
),
active_users_p90 as (
  select
    au.user_id,
    au.display_name,
    au.reputation,
    au.creationdate,
    au.lastaccessdate,
    au.upvotes,
    au.downvotes,
    au.rep_dr,
    au.rep_ventile,
    p.p90_rep
  from active_users au
  cross join (
    select percentile_disc(0.9) within group (order by reputation) as p90_rep
    from users
    where creationdate is not null
  ) p
),
recent_questions as (
  select
    p.id as question_id,
    p.owneruserid as owner_user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.closeddate,
    p.title,
    p.tags,
    -- turn tags like '<a><b>' into array ['a','b']
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_array,
    length(coalesce(p.title, '')) as title_len,
    coalesce(nullif(p.contentlicense,''), 'Unknown') as content_license
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as owner_user_id,
    a.score as answer_score,
    a.creationdate as answer_date,
    case when a.id = q.acceptedanswerid then 1 else 0 end as is_accepted
  from posts a
  join posts q on q.id = a.parentid and a.posttypeid = 2
),
answer_stats as (
  select
    a.question_id,
    count(*) as total_answers,
    sum(case when a.is_accepted = 1 then 1 else 0 end) as accepted_answers,
    avg(a.answer_score) as avg_answer_score,
    max(a.answer_date) as last_answer_date
  from answers a
  group by a.question_id
),
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as total_votes,
    count(distinct v.userid) filter (where v.userid is not null) as unique_voters
  from votes v
  group by v.postid
),
comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    avg(length(c.text)) as avg_comment_len,
    max(length(c.text)) as max_comment_len,
    min(c.creationdate) as first_comment_date,
    max(c.creationdate) as last_comment_date
  from comments c
  group by c.postid
),
history_flags as (
  select
    ph.postid,
    bool_or(ph.posthistorytypeid in (10,35)) as was_closed_or_migrated,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as last_moderation_date
  from posthistory ph
  group by ph.postid
),
dup_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
    count(*) filter (where pl.linktypeid = 1) as related_links
  from postlinks pl
  group by pl.postid
),
tag_dim as (
  select
    t.tagname,
    t.count as tag_total_count,
    -- convert boolean flags to integers to allow numeric aggregation and coalesce with integers
    case when t.ismoderatoronly is true then 1 else 0 end as is_mod_only,
    case when t.isrequired is true then 1 else 0 end as is_required
  from tags t
),
question_tags as (
  select
    rq.question_id,
    lower(trim(t)) as tag
  from recent_questions rq
  left join lateral unnest(rq.tag_array) as t on true
),
question_tag_enriched as (
  select
    qt.question_id,
    qt.tag,
    td.tag_total_count,
    td.is_mod_only,
    td.is_required,
    dense_rank() over (order by td.tag_total_count desc nulls last, qt.tag) as tag_pop_rank
  from question_tags qt
  left join tag_dim td on td.tagname = qt.tag
),
question_tag_stats as (
  select
    qte.question_id,
    count(*) as tag_count,
    max(qte.tag_total_count) as max_tag_popularity,
    min(qte.tag_total_count) as min_tag_popularity,
    sum(case when qte.is_mod_only = 1 then 1 else 0 end) as mod_only_tag_count,
    sum(case when qte.is_required = 1 then 1 else 0 end) as required_tag_count
  from question_tag_enriched qte
  group by qte.question_id
),
owner_users as (
  select
    au.user_id,
    au.display_name,
    au.reputation,
    au.creationdate,
    au.lastaccessdate,
    au.upvotes,
    au.downvotes,
    au.rep_ventile,
    case when au.reputation >= au.p90_rep then 1 else 0 end as is_top10pct
  from active_users_p90 au
),
question_rollup as (
  select
    rq.question_id,
    rq.owner_user_id,
    rq.creationdate,
    rq.score,
    rq.viewcount,
    rq.answercount,
    rq.favoritecount,
    rq.commentcount,
    rq.closeddate,
    rq.title,
    rq.title_len,
    rq.content_license,
    coalesce(asg.total_answers, 0) as total_answers,
    coalesce(asg.accepted_answers, 0) as accepted_answers,
    asg.avg_answer_score,
    asg.last_answer_date,
    coalesce(va.upvotes, 0) as upvotes,
    coalesce(va.downvotes, 0) as downvotes,
    coalesce(va.favorites, 0) as favorites,
    coalesce(va.bounty_total, 0) as bounty_total,
    coalesce(va.total_votes, 0) as total_votes,
    coalesce(va.unique_voters, 0) as unique_voters,
    coalesce(ca.comment_count, 0) as comments_total,
    ca.avg_comment_len,
    ca.max_comment_len,
    ca.first_comment_date,
    ca.last_comment_date,
    coalesce(hf.was_closed_or_migrated, false) as was_closed_or_migrated,
    coalesce(hf.edit_events, 0) as edit_events,
    hf.last_moderation_date,
    coalesce(dl.duplicate_marks, 0) as duplicate_marks,
    coalesce(dl.related_links, 0) as related_links
  from recent_questions rq
  left join answer_stats asg on asg.question_id = rq.question_id
  left join vote_agg va on va.postid = rq.question_id
  left join comment_agg ca on ca.postid = rq.question_id
  left join history_flags hf on hf.postid = rq.question_id
  left join dup_links dl on dl.postid = rq.question_id
),
scored as (
  select
    qr.question_id,
    qr.owner_user_id,
    qr.creationdate,
    qr.score,
    qr.viewcount,
    qr.answercount,
    qr.favoritecount,
    qr.commentcount,
    qr.closeddate,
    qr.title,
    qr.title_len,
    qr.content_license,
    qr.total_answers,
    qr.accepted_answers,
    qr.avg_answer_score,
    qr.last_answer_date,
    qr.upvotes,
    qr.downvotes,
    qr.favorites,
    qr.bounty_total,
    qr.total_votes,
    qr.unique_voters,
    qr.comments_total,
    qr.avg_comment_len,
    qr.max_comment_len,
    qr.first_comment_date,
    qr.last_comment_date,
    qr.was_closed_or_migrated,
    qr.edit_events,
    qr.last_moderation_date,
    qr.duplicate_marks,
    qr.related_links,
    coalesce(nullif(qr.viewcount,0),1) as view_div,
    (qr.upvotes - qr.downvotes) as net_votes,
    case
      when qr.answercount > 0 then (cast(qr.accepted_answers as numeric) / qr.answercount)
      else null
    end as acceptance_ratio,
    (coalesce(qr.upvotes,0)*3 + coalesce(qr.favorites,0)*2 + coalesce(qr.bounty_total,0)/50.0
      + coalesce(qr.comments_total,0)*0.5 + coalesce(qr.related_links,0)*0.1
      - coalesce(qr.downvotes,0)*2 - coalesce(qr.duplicate_marks,0)*5) as raw_engagement,
    case
      when qr.closeddate is not null then 0
      when qr.was_closed_or_migrated then 0.25
      else 1
    end as visibility_factor
  from question_rollup qr
),
temporal as (
  select
    s.question_id,
    s.owner_user_id,
    s.creationdate,
    s.score,
    s.viewcount,
    s.answercount,
    s.favoritecount,
    s.commentcount,
    s.closeddate,
    s.title,
    s.title_len,
    s.content_license,
    s.total_answers,
    s.accepted_answers,
    s.avg_answer_score,
    s.last_answer_date,
    s.upvotes,
    s.downvotes,
    s.favorites,
    s.bounty_total,
    s.total_votes,
    s.unique_voters,
    s.comments_total,
    s.avg_comment_len,
    s.max_comment_len,
    s.first_comment_date,
    s.last_comment_date,
    s.was_closed_or_migrated,
    s.edit_events,
    s.last_moderation_date,
    s.duplicate_marks,
    s.related_links,
    s.view_div,
    s.net_votes,
    s.acceptance_ratio,
    s.raw_engagement,
    s.visibility_factor,
    date_trunc('month', s.creationdate) as month_bucket,
    avg(s.score) over (partition by date_trunc('month', s.creationdate)) as monthly_avg_score,
    avg(s.raw_engagement) over (partition by date_trunc('month', s.creationdate)) as monthly_avg_engagement,
    row_number() over (partition by date_trunc('month', s.creationdate) order by s.raw_engagement desc, s.question_id) as monthly_engagement_rank,
    lag(s.raw_engagement) over (partition by s.owner_user_id order by s.creationdate) as prev_engagement_by_owner,
    sum(case when s.accepted_answers > 0 then 1 else 0 end) over (partition by s.owner_user_id) as owner_questions_with_accept
  from scored s
),
final_enriched as (
  select
    t.question_id,
    t.owner_user_id,
    t.creationdate,
    t.score,
    t.viewcount,
    t.answercount,
    t.favoritecount,
    t.commentcount,
    t.closeddate,
    t.title,
    t.title_len,
    t.content_license,
    t.total_answers,
    t.accepted_answers,
    t.avg_answer_score,
    t.last_answer_date,
    t.upvotes,
    t.downvotes,
    t.favorites,
    t.bounty_total,
    t.total_votes,
    t.unique_voters,
    t.comments_total,
    t.avg_comment_len,
    t.max_comment_len,
    t.first_comment_date,
    t.last_comment_date,
    t.was_closed_or_migrated,
    t.edit_events,
    t.last_moderation_date,
    t.duplicate_marks,
    t.related_links,
    t.view_div,
    t.net_votes,
    t.acceptance_ratio,
    t.raw_engagement,
    t.visibility_factor,
    t.month_bucket,
    t.monthly_avg_score,
    t.monthly_avg_engagement,
    t.monthly_engagement_rank,
    t.prev_engagement_by_owner,
    t.owner_questions_with_accept,
    ou.display_name as owner_name,
    ou.reputation as owner_reputation,
    ou.upvotes as owner_upvotes,
    ou.downvotes as owner_downvotes,
    ou.rep_ventile as owner_rep_ventile,
    ou.is_top10pct as owner_top10
  from temporal t
  left join owner_users ou on ou.user_id = t.owner_user_id
),
final_scored as (
  select
    fe.question_id,
    fe.owner_user_id,
    fe.creationdate,
    fe.score,
    fe.viewcount,
    fe.answercount,
    fe.favoritecount,
    fe.commentcount,
    fe.closeddate,
    fe.title,
    fe.title_len,
    fe.content_license,
    fe.total_answers,
    fe.accepted_answers,
    fe.avg_answer_score,
    fe.last_answer_date,
    fe.upvotes,
    fe.downvotes,
    fe.favorites,
    fe.bounty_total,
    fe.total_votes,
    fe.unique_voters,
    fe.comments_total,
    fe.avg_comment_len,
    fe.max_comment_len,
    fe.first_comment_date,
    fe.last_comment_date,
    fe.was_closed_or_migrated,
    fe.edit_events,
    fe.last_moderation_date,
    fe.duplicate_marks,
    fe.related_links,
    fe.view_div,
    fe.net_votes,
    fe.acceptance_ratio,
    fe.raw_engagement,
    fe.visibility_factor,
    fe.month_bucket,
    fe.monthly_avg_score,
    fe.monthly_avg_engagement,
    fe.monthly_engagement_rank,
    fe.prev_engagement_by_owner,
    fe.owner_questions_with_accept,
    fe.owner_name,
    fe.owner_reputation,
    fe.owner_upvotes,
    fe.owner_downvotes,
    fe.owner_rep_ventile,
    fe.owner_top10,
    coalesce(qts.tag_count, 0) as tag_count,
    qts.max_tag_popularity,
    qts.min_tag_popularity,
    coalesce(qts.mod_only_tag_count, 0) as mod_only_tag_count,
    coalesce(qts.required_tag_count, 0) as required_tag_count,
    (fe.raw_engagement * fe.visibility_factor) / fe.view_div
      + coalesce(fe.acceptance_ratio, 0) * 2
      + case when fe.avg_comment_len > 300 then 0.5 else 0 end
      + case when fe.owner_top10 = 1 then 0.25 else 0 end
      - case when fe.duplicate_marks > 0 then 1 else 0 end
      - case when coalesce(qts.mod_only_tag_count,0) > 0 then 0.1 else 0 end
      as composite_score,
    case
      when fe.closeddate is not null then 'Closed'
      when fe.duplicate_marks > 0 then 'Duplicate'
      when fe.accepted_answers > 0 then 'Resolved'
      when fe.answercount = 0 and fe.viewcount > 0 then 'Unanswered'
      else 'Open'
    end as status_bucket
  from final_enriched fe
  left join question_tag_stats qts on qts.question_id = fe.question_id
),
ranked as (
  select
    fs.*,
    rank() over (partition by fs.owner_user_id order by fs.composite_score desc nulls last, fs.creationdate desc, fs.question_id) as owner_best_rank,
    dense_rank() over (order by fs.composite_score desc nulls last) as global_dense_rank
  from final_scored fs
)
select
  r.question_id,
  r.title,
  r.owner_user_id,
  coalesce(r.owner_name, '(unknown)') as owner_name,
  r.owner_reputation,
  r.creationdate,
  r.month_bucket,
  r.status_bucket,
  r.score as post_score,
  r.net_votes,
  r.viewcount,
  r.answercount,
  r.accepted_answers,
  round(coalesce(r.acceptance_ratio,0), 3) as acceptance_ratio,
  r.total_answers,
  r.upvotes,
  r.downvotes,
  r.favorites,
  r.bounty_total,
  r.total_votes,
  r.unique_voters,
  r.comments_total,
  round(coalesce(r.avg_comment_len,0), 2) as avg_comment_len,
  r.max_comment_len,
  r.was_closed_or_migrated,
  r.edit_events,
  r.duplicate_marks,
  r.related_links,
  r.tag_count,
  r.max_tag_popularity,
  r.min_tag_popularity,
  r.mod_only_tag_count,
  r.required_tag_count,
  round(r.raw_engagement, 2) as raw_engagement,
  round((r.raw_engagement * r.visibility_factor), 2) as vis_adj_engagement,
  round(r.composite_score, 4) as composite_score,
  r.monthly_avg_score,
  r.monthly_avg_engagement,
  r.monthly_engagement_rank,
  r.prev_engagement_by_owner,
  r.owner_questions_with_accept,
  r.owner_rep_ventile,
  r.owner_top10,
  r.owner_best_rank,
  r.global_dense_rank
from ranked r
where
  (
    r.owner_top10 = 1
    or r.composite_score > (
      select coalesce(percentile_disc(0.95) within group (order by composite_score), 0)
      from final_scored
    )
    or r.status_bucket in ('Unanswered', 'Duplicate')
  )
  and coalesce(r.title_len, 0) > 0
  and (r.content_license is null or r.content_license not like '%CC0%')
order by
  r.global_dense_rank,
  r.owner_best_rank,
  r.question_id
limit 500;