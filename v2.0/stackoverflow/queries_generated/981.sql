-- {"query": "981.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3653} 
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
  where u.creationdate >= now() - interval '5 years'
),
question_posts as (
  select p.*
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.*
  from posts p
  where p.posttypeid = 2
),
q_activity as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as q_created,
    q.score as q_score,
    q.viewcount as q_views,
    q.title,
    q.tags,
    q.acceptedanswerid,
    q.closeddate,
    q.communityowneddate,
    count(a.id) as answers_count,
    sum(case when a.score > 0 then 1 else 0 end) as pos_answers,
    min(a.creationdate) filter (where a.id is not null) as first_answer_at
  from question_posts q
  left join answer_posts a on a.parentid = q.id
  group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid, q.closeddate, q.communityowneddate
),
first_comment_per_q as (
  select
    c.postid as question_id,
    min(c.creationdate) as first_comment_at,
    max(c.creationdate) as last_comment_at,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments
  from comments c
  join question_posts q on q.id = c.postid
  group by c.postid
),
badge_summaries as (
  select
    u.id as user_id,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from users u
  left join badges b on b.userid = u.id
  group by u.id
),
vote_agg as (
  select
    p.id as post_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from posts p
  left join votes v on v.postid = p.id
  group by p.id
),
close_events as (
  select
    ph.postid as question_id,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    array_agg(distinct ph.comment) filter (where ph.posthistorytypeid = 10 and ph.comment is not null) as close_reasons_raw
  from posthistory ph
  join question_posts q on q.id = ph.postid
  group by ph.postid
),
duplicates as (
  select
    pl.postid as dup_question_id,
    pl.relatedpostid as original_question_id,
    min(pl.creationdate) as first_dup_link_at,
    count(*) as dup_link_count
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
tag_expansion as (
  select
    q.id as question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from question_posts q
  where q.tags is not null
),
top_tags as (
  select
    te.tag,
    count(*) as tag_q_count,
    row_number() over (order by count(*) desc, te.tag) as tag_rank
  from tag_expansion te
  group by te.tag
),
user_activity as (
  select
    u.user_id,
    count(distinct qa.question_id) as questions_count,
    sum(qa.answers_count) as answers_on_their_questions,
    sum(coalesce(va.upvotes,0)) as total_upvotes_on_questions,
    sum(coalesce(va.downvotes,0)) as total_downvotes_on_questions,
    sum(coalesce(va.bounty_total,0)) as total_bounty_on_questions,
    count(distinct a.id) as answers_authored,
    sum(case when a.score > 0 then 1 else 0 end) as answers_authored_positive,
    min(qa.q_created) as first_question_at,
    max(qa.q_created) as last_question_at
  from recent_users u
  left join q_activity qa on qa.asker_id = u.user_id
  left join vote_agg va on va.post_id = qa.question_id
  left join posts a on a.posttypeid = 2 and a.owneruserid = u.user_id
  group by u.user_id
),
accepted_answer_latency as (
  select
    qa.question_id,
    qa.asker_id,
    qa.q_created,
    aa.creationdate as accepted_answer_created,
    extract(epoch from (aa.creationdate - qa.q_created)) / 3600.0 as hours_to_accept
  from q_activity qa
  join posts aa on aa.id = qa.acceptedanswerid
),
cohort_stats as (
  select
    ru.cohort_month,
    count(distinct ru.user_id) as users_in_cohort,
    avg(ua.questions_count) as avg_qs_per_user,
    avg(ua.answers_authored) as avg_as_per_user,
    percentile_cont(0.5) within group (order by ua.total_upvotes_on_questions) as p50_q_upvotes,
    avg(case when aal.hours_to_accept is not null then aal.hours_to_accept end) as avg_hours_to_accept
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join accepted_answer_latency aal on aal.asker_id = ru.user_id
  group by ru.cohort_month
),
ranked_questions as (
  select
    qa.question_id,
    qa.asker_id,
    qa.q_created,
    qa.q_score,
    qa.q_views,
    qa.answers_count,
    qa.pos_answers,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.favorites,0) as favorites,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(fc.comment_count,0) as comment_count,
    coalesce(fc.pos_comments,0) as pos_comments,
    coalesce(extract(epoch from (fc.first_comment_at - qa.q_created))/60.0, null) as minutes_to_first_comment,
    coalesce(extract(epoch from (qa.first_answer_at - qa.q_created))/60.0, null) as minutes_to_first_answer,
    row_number() over (
      partition by date_trunc('month', qa.q_created)
      order by
        (qa.q_score * 3 + coalesce(va.upvotes,0) * 2 - coalesce(va.downvotes,0) + coalesce(va.favorites,0) + least(coalesce(qa.answers_count,0), 10)) desc,
        qa.q_views desc,
        qa.q_created asc
    ) as month_rank
  from q_activity qa
  left join vote_agg va on va.post_id = qa.question_id
  left join first_comment_per_q fc on fc.question_id = qa.question_id
),
heavy_users as (
  select
    ua.user_id,
    ua.questions_count,
    ua.answers_authored,
    dense_rank() over (order by ua.questions_count desc, ua.answers_authored desc) as activity_rank
  from user_activity ua
),
string_metrics as (
  select
    q.question_id,
    length(coalesce(q.title,'')) as title_len,
    length(coalesce(p.body, '')) as body_len,
    length(regexp_replace(coalesce(p.body,''), '<[^>]+>', '', 'g')) as body_text_len,
    (length(coalesce(p.body,'')) - length(regexp_replace(coalesce(p.body,''), '<[^>]+>', '', 'g'))) as body_markup_len,
    case
      when p.ownerdisplayname is null or trim(p.ownerdisplayname) = '' then '(unknown)'
      else initcap(lower(p.ownerdisplayname))
    end as owner_display_norm
  from ranked_questions q
  join posts p on p.id = q.question_id
),
null_logic_demo as (
  select
    q.question_id,
    coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, '(anon)') as effective_owner_display,
    case when p.owneruserid is null then 1 else 0 end as is_orphaned,
    case when p.communityowneddate is not null then 1 else 0 end as is_community_owned
  from question_posts p
  join ranked_questions q on q.question_id = p.id
  left join users u on u.id = p.owneruserid
),
top_related_original as (
  select
    d.dup_question_id,
    d.original_question_id,
    row_number() over (partition by d.dup_question_id order by d.dup_link_count desc, d.first_dup_link_at asc) as rn
  from duplicates d
),
user_geo as (
  select
    ru.user_id,
    case
      when ru.location ilike '%united states%' or ru.location ilike '%usa%' or ru.location ilike '%u.s.%' then 'US'
      when ru.location ilike '%india%' then 'IN'
      when ru.location ilike '%united kingdom%' or ru.location ilike '%uk%' then 'UK'
      when ru.location ilike '%germany%' then 'DE'
      when ru.location ilike '%canada%' then 'CA'
      when ru.location is null or trim(ru.location) = '' then 'UNK'
      else 'OTHER'
    end as region
  from recent_users ru
),
final_set as (
  select
    q.question_id,
    q.asker_id,
    ru.displayname as asker_displayname,
    sm.owner_display_norm,
    nl.effective_owner_display,
    q.q_created,
    date_trunc('month', q.q_created) as q_month,
    q.q_score,
    q.q_views,
    q.answers_count,
    q.pos_answers,
    q.upvotes,
    q.downvotes,
    q.favorites,
    q.bounty_total,
    q.comment_count,
    q.pos_comments,
    q.minutes_to_first_comment,
    q.minutes_to_first_answer,
    sm.title_len,
    sm.body_len,
    sm.body_text_len,
    sm.body_markup_len,
    coalesce(aal.hours_to_accept, null) as hours_to_accept,
    ce.first_closed_at,
    ce.last_reopened_at,
    ce.close_events,
    case when ce.close_events > 0 then 1 else 0 end as ever_closed,
    array_to_string(ce.close_reasons_raw, '|') as close_reasons_concat,
    tr.tag as sample_tag,
    tt.tag_rank as sample_tag_rank,
    ua.questions_count as asker_questions_count,
    ua.answers_authored as asker_answers_authored,
    hu.activity_rank as asker_activity_rank,
    bs.total_badges,
    bs.gold_badges,
    bs.silver_badges,
    bs.bronze_badges,
    bs.tag_badges,
    ug.region as asker_region,
    dr.original_question_id as likely_original_id,
    case when rq2.question_id is not null then 1 else 0 end as also_top_in_prev_month
  from ranked_questions q
  left join recent_users ru on ru.user_id = q.asker_id
  left join string_metrics sm on sm.question_id = q.question_id
  left join null_logic_demo nl on nl.question_id = q.question_id
  left join accepted_answer_latency aal on aal.question_id = q.question_id
  left join close_events ce on ce.question_id = q.question_id
  left join lateral (
    select te.tag
    from tag_expansion te
    where te.question_id = q.question_id
    order by te.tag asc
    limit 1
  ) tr on true
  left join top_tags tt on tt.tag = tr.tag
  left join user_activity ua on ua.user_id = q.asker_id
  left join heavy_users hu on hu.user_id = q.asker_id
  left join badge_summaries bs on bs.user_id = q.asker_id
  left join user_geo ug on ug.user_id = q.asker_id
  left join top_related_original dro on dro.dup_question_id = q.question_id and dro.rn = 1
  left join duplicates dr on dr.dup_question_id = q.question_id and dr.original_question_id = dro.original_question_id
  left join ranked_questions rq2
    on rq2.asker_id = q.asker_id
   and date_trunc('month', rq2.q_created) = date_trunc('month', q.q_created) - interval '1 month'
   and rq2.month_rank <= 10
  where q.month_rank <= 50
),
prev_month_top as (
  select
    date_trunc('month', q_created) as q_month,
    question_id
  from ranked_questions
  where month_rank <= 10
)
select
  f.question_id,
  f.asker_id,
  coalesce(f.asker_displayname, '(unknown)') as asker_displayname,
  f.owner_display_norm,
  f.effective_owner_display,
  f.q_created,
  f.q_month,
  f.q_score,
  f.q_views,
  f.answers_count,
  f.pos_answers,
  f.upvotes,
  f.downvotes,
  f.favorites,
  f.bounty_total,
  f.comment_count,
  f.pos_comments,
  round(f.minutes_to_first_comment::numeric, 2) as minutes_to_first_comment,
  round(f.minutes_to_first_answer::numeric, 2) as minutes_to_first_answer,
  f.title_len,
  f.body_len,
  f.body_text_len,
  f.body_markup_len,
  round(f.hours_to_accept::numeric, 2) as hours_to_accept,
  f.first_closed_at,
  f.last_reopened_at,
  f.close_events,
  f.ever_closed,
  f.close_reasons_concat,
  f.sample_tag,
  f.sample_tag_rank,
  f.asker_questions_count,
  f.asker_answers_authored,
  f.asker_activity_rank,
  f.total_badges,
  f.gold_badges,
  f.silver_badges,
  f.bronze_badges,
  f.tag_badges,
  f.asker_region,
  f.likely_original_id,
  f.also_top_in_prev_month,
  case
    when f.q_score >= 10 and f.answers_count >= 2 and coalesce(f.hours_to_accept, 9999) < 24 then 'fast-accepted-highscore'
    when f.ever_closed = 1 and coalesce(f.downvotes,0) > coalesce(f.upvotes,0) then 'controversial-closed'
    when f.bounty_total > 0 then 'bountied'
    else 'normal'
  end as category,
  row_number() over (
    partition by f.q_month
    order by
      (f.q_score * 3 + f.upvotes * 2 - f.downvotes + f.favorites + least(f.answers_count,10)) desc,
      f.q_views desc,
      f.q_created asc
  ) as reranked_month_rownum,
  count(*) over (partition by f.q_month) as month_result_count
from final_set f
where (
    f.sample_tag is null
    or not exists (
      select 1
      from prev_month_top pmt
      where pmt.q_month = f.q_month - interval '1 month'
        and pmt.question_id = f.question_id
    )
  )
  and coalesce(f.q_views,0) >= 0
  and (f.first_closed_at is null or f.last_reopened_at is not null or f.close_events <= 1)
order by f.q_month desc, reranked_month_rownum asc
limit 500;