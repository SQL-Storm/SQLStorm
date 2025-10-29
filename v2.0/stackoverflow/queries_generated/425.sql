-- {"query": "425.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3593} 
with params as (
  select
    0.15::numeric as top_user_percent,
    365 as recent_days
),
-- High-rep cohort and user stats
user_base as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    percentile_cont(1 - p.top_user_percent) within group (order by u.reputation) over () as rep_cutoff
  from users u
  cross join params p
),
user_cohort as (
  select
    ub.*,
    case when ub.reputation >= ub.rep_cutoff then 1 else 0 end as is_top
  from user_base ub
),
-- Posts in recent window with derived features
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.favoritecount,
    p.answercount,
    p.commentcount,
    p.acceptedanswerid,
    p.title,
    p.tags,
    p.closeddate,
    p.contentlicense,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer,
    case when p.closeddate is not null then 1 else 0 end as is_closed,
    nullif(trim(p.title), '') as title_trimmed
  from posts p
  cross join params prm
  where p.creationdate >= (select max(creationdate) from posts) - (prm.recent_days || ' days')::interval
),
-- Tag extraction (simple split), only for questions
question_tags as (
  select
    rp.id as postid,
    unnest(string_to_array(substring(rp.tags, 2, greatest(length(rp.tags)-2,0)), '><')) as tagname
  from recent_posts rp
  where rp.is_question = 1
),
-- Aggregate votes per post with window rank
votes_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate is not null
  group by v.postid
),
votes_ranked as (
  select
    va.*,
    rank() over (order by (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) desc, va.total_votes desc, coalesce(va.favorites,0) desc, va.postid) as vote_rank
  from votes_agg va
),
-- Comments sentiment proxy (length, punctuation density)
comment_metrics as (
  select
    c.postid,
    count(*) as comments,
    coalesce(sum(c.score),0) as comment_score,
    avg(length(c.text)) as avg_comment_len,
    avg((length(c.text) - length(replace(replace(replace(replace(c.text,'.',''), '!',''), '?',''), ',','')))::numeric / greatest(length(c.text),1)) as punct_density
  from comments c
  group by c.postid
),
-- PostHistory closures and edits
posthistory_flags as (
  select
    ph.postid,
    max(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as ever_closed_or_migrated,
    max(case when ph.posthistorytypeid in (24) then 1 else 0 end) as has_suggested_edit,
    max(case when ph.posthistorytypeid in (11,13) then 1 else 0 end) as ever_reopened_or_undeleted,
    sum(case when ph.posthistorytypeid in (4,5,6,8,9) then 1 else 0 end) as edit_events
  from posthistory ph
  group by ph.postid
),
-- Duplicate relationships
dup_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as dup_count_as_duplicate,
    count(*) filter (where pl.linktypeid = 1) as linked_count
  from postlinks pl
  group by pl.postid
),
-- Tag popularity lookup
tag_pop as (
  select
    lower(t.tagname) as tagname,
    t.count as global_tag_count,
    t.ismoderatoronly::int as is_mod_only,
    t.isrequired::int as is_required
  from tags t
),
-- Per-post tag metrics
post_tag_metrics as (
  select
    qt.postid,
    count(*) as tag_count,
    sum(tp.global_tag_count) as sum_tag_popularity,
    avg(tp.global_tag_count::numeric) as avg_tag_popularity,
    max(tp.global_tag_count) as max_tag_popularity,
    sum(tp.is_mod_only) as mod_only_tags,
    sum(tp.is_required) as required_tags
  from question_tags qt
  left join tag_pop tp on tp.tagname = lower(qt.tagname)
  group by qt.postid
),
-- Owner user enrichment
owner_enriched as (
  select
    rp.id as postid,
    uc.id as ownerid,
    uc.displayname as owner_displayname,
    uc.reputation as owner_reputation,
    uc.is_top,
    extract(epoch from (rp.creationdate - uc.creationdate))/86400.0 as owner_tenure_days,
    case when uc.location ilike '%remote%' then 1 else 0 end as owner_remote_flag,
    uc.websiteurl
  from recent_posts rp
  left join user_cohort uc on rp.owneruserid = uc.id
),
-- Compute title/text complexity
text_metrics as (
  select
    rp.id as postid,
    coalesce(length(rp.title_trimmed), 0) as title_len,
    case
      when rp.title_trimmed is null then 0
      else regexp_count(rp.title_trimmed, '\w+')
    end as title_word_count,
    case
      when rp.tags is null then 0
      else length(rp.tags) - length(replace(rp.tags, '><','')) + 1
    end as approx_tag_slots
  from recent_posts rp
),
-- Answers linkage and acceptance info
answer_info as (
  select
    q.id as questionid,
    count(a.id) as answers_total,
    sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted,
    max(a.score) as max_answer_score,
    avg(a.score::numeric) as avg_answer_score
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),
-- Windowed popularity metric across recents
post_popularity as (
  select
    rp.id as postid,
    rp.score,
    rp.viewcount,
    coalesce(rp.favoritecount,0) as favoritecount,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.total_votes,0) as total_votes,
    dense_rank() over (order by rp.viewcount desc nulls last) as view_rank,
    percent_rank() over (order by rp.score) as score_percentile,
    ntile(10) over (order by coalesce(va.upvotes,0) - coalesce(va.downvotes,0) desc) as netvote_decile
  from recent_posts rp
  left join votes_agg va on va.postid = rp.id
),
-- Build a synthetic scoring for benchmarking various expressions
synthetic_score as (
  select
    rp.id as postid,
    (coalesce(pp.score,0) * 2)
    + (greatest(coalesce(pp.upvotes,0) - coalesce(pp.downvotes,0), 0) * 3)
    + (least(coalesce(pp.viewcount,0) / nullif(tm.title_word_count,0), 1000))
    + (coalesce(cm.comment_score,0))
    + (coalesce(pf.edit_events,0) * 0.5)
    + (case when oe.is_top = 1 then 25 else 0 end)
    - (case when rp.is_closed = 1 then 10 else 0 end)
    + (coalesce(ptm.avg_tag_popularity,0) / 100.0)
    + (case when ai.has_accepted > 0 then 15 else 0 end)
    + (case when oe.owner_remote_flag = 1 then 2 else 0 end)
    + (case when rp.is_answer = 1 then 5 else 0 end)
    + (case when rp.is_question = 1 then 8 else 0 end)
    as synth_score
  from recent_posts rp
  left join post_popularity pp on pp.postid = rp.id
  left join text_metrics tm on tm.postid = rp.id
  left join comment_metrics cm on cm.postid = rp.id
  left join posthistory_flags pf on pf.postid = rp.id
  left join owner_enriched oe on oe.postid = rp.id
  left join post_tag_metrics ptm on ptm.postid = rp.id
  left join answer_info ai on ai.questionid = rp.id
),
-- Build cohorts by multiple criteria
cohorts as (
  select
    rp.id as postid,
    case
      when rp.is_question = 1 and coalesce(ptm.tag_count,0) >= 5 then 'Q_many_tags'
      when rp.is_question = 1 and coalesce(ptm.tag_count,0) between 3 and 4 then 'Q_mid_tags'
      when rp.is_question = 1 then 'Q_few_tags'
      when rp.is_answer = 1 and coalesce(pp.score,0) >= 5 then 'A_high_score'
      when rp.is_answer = 1 then 'A_other'
      else 'Other'
    end as cohort_label
  from recent_posts rp
  left join post_tag_metrics ptm on ptm.postid = rp.id
  left join post_popularity pp on pp.postid = rp.id
),
-- Cross-cohort ranking using window functions and partitioning
ranked as (
  select
    rp.id as postid,
    rp.creationdate,
    c.cohort_label,
    s.synth_score,
    row_number() over (partition by c.cohort_label order by s.synth_score desc, rp.creationdate desc, rp.id) as rn_in_cohort,
    rank() over (order by s.synth_score desc, rp.creationdate desc, rp.id) as global_rank,
    sum(case when rp.is_question = 1 then 1 else 0 end) over () as total_questions,
    sum(case when rp.is_answer = 1 then 1 else 0 end) over () as total_answers
  from recent_posts rp
  join synthetic_score s on s.postid = rp.id
  join cohorts c on c.postid = rp.id
),
-- Build a contrasting set via set operator
top_vs_bottom as (
  (
    select r.postid, r.cohort_label, 'TOP' as side, r.synth_score
    from ranked r
    where r.global_rank <= 100
  )
  union all
  (
    select r.postid, r.cohort_label, 'BOTTOM' as side, r.synth_score
    from ranked r
    where r.global_rank > (select max(global_rank) from ranked) - 100
  )
),
-- Correlated subquery example: latest comment text snippet per post
latest_comment as (
  select
    c.postid,
    (select c2.text
     from comments c2
     where c2.postid = c.postid
     order by c2.creationdate desc, c2.id desc
     limit 1) as latest_comment_text
  from comments c
  group by c.postid
),
-- Build final enriched result set
final as (
  select
    r.postid,
    r.cohort_label,
    r.global_rank,
    r.rn_in_cohort,
    s.synth_score,
    rp.posttypeid,
    rp.score as post_score,
    rp.viewcount,
    pp.upvotes,
    pp.downvotes,
    pp.favoritecount,
    ptm.tag_count,
    ptm.avg_tag_popularity,
    oe.ownerid,
    oe.owner_displayname,
    oe.owner_reputation,
    oe.is_top as owner_is_top,
    oe.owner_tenure_days,
    oe.websiteurl as owner_websiteurl,
    coalesce(lc.latest_comment_text, '(no comments)') as latest_comment_text,
    coalesce(cm.comments,0) as comment_count,
    cm.avg_comment_len,
    cm.punct_density,
    pf.ever_closed_or_migrated,
    pf.has_suggested_edit,
    pf.ever_reopened_or_undeleted,
    pf.edit_events,
    dl.dup_count_as_duplicate,
    dl.linked_count,
    ai.answers_total,
    ai.has_accepted,
    ai.max_answer_score,
    ai.avg_answer_score,
    tm.title_len,
    tm.title_word_count,
    tm.approx_tag_slots,
    pr.view_rank,
    pr.score_percentile,
    pr.netvote_decile
  from ranked r
  join synthetic_score s on s.postid = r.postid
  join recent_posts rp on rp.id = r.postid
  left join post_popularity pr on pr.postid = r.postid
  left join post_tag_metrics ptm on ptm.postid = r.postid
  left join owner_enriched oe on oe.postid = r.postid
  left join votes_agg pp on pp.postid = r.postid
  left join comment_metrics cm on cm.postid = r.postid
  left join posthistory_flags pf on pf.postid = r.postid
  left join dup_links dl on dl.postid = r.postid
  left join answer_info ai on ai.questionid = r.postid
  left join text_metrics tm on tm.postid = r.postid
  left join latest_comment lc on lc.postid = r.postid
)
select
  f.*,
  tvb.side as comparison_side,
  case
    when f.owner_is_top = 1 and f.has_accepted = 1 then 'ELITE_ACCEPTED'
    when f.owner_is_top = 1 then 'ELITE'
    when f.has_accepted = 1 then 'ACCEPTED_BY_NON_ELITE'
    else 'OTHER'
  end as strat_label,
  -- Null and string logic stressors
  coalesce(nullif(trim(lower(regexp_replace(f.owner_displayname, '\s+', ' ', 'g'))), ''), 'anonymous') as owner_displayname_norm,
  case when f.latest_comment_text ilike '%thanks%' then 1 else 0 end as latest_comment_thanks_flag
from final f
left join top_vs_bottom tvb on tvb.postid = f.postid
where
  -- complicated predicate combining numeric, null, and string conditions
  (
    (f.cohort_label like 'Q_%' and coalesce(f.tag_count,0) >= 1 and (f.post_score > 0 or f.has_accepted = 1))
    or
    (f.cohort_label like 'A_%' and f.post_score >= 0 and coalesce(f.comment_count,0) >= 0)
  )
  and (
    (f.owner_reputation is null or f.owner_reputation >= 100)
    and (f.avg_comment_len is null or f.avg_comment_len <= 2000)
  )
  and (
    f.view_rank <= 500
    or f.netvote_decile <= 3
    or (f.score_percentile >= 0.95 and f.post_score >= 5)
  )
order by
  f.global_rank nulls last,
  f.rn_in_cohort,
  f.postid
limit 500;