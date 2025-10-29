-- {"query": "358.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3234} 
with
-- recent users and activity stats
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
    dense_rank() over (order by u.creationdate desc) as recency_rank
  from users u
),
-- questions and their tag arrays
questions as (
  select
    p.id as q_id,
    p.owneruserid as q_ownerid,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount as q_views,
    p.title,
    p.tags,
    p.acceptedanswerid,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_arr
  from posts p
  where p.posttypeid = 1
),
-- answers table with acceptance and timing
answers as (
  select
    a.id as a_id,
    a.parentid as q_id,
    a.owneruserid as a_ownerid,
    a.creationdate as a_created,
    a.score as a_score,
    a.body as a_body,
    case when a.id = q.acceptedanswerid then 1 else 0 end as is_accepted,
    extract(epoch from (a.creationdate - q.q_created))::bigint as secs_after_q
  from posts a
  join questions q on q.q_id = a.parentid
  where a.posttypeid = 2
),
-- votes aggregated per post
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) filter (where v.votetypeid in (2,3)) as total_votes
  from votes v
  group by v.postid
),
-- comment sentiment proxy by punctuation density and length
comment_features as (
  select
    c.postid,
    count(*) as comment_count,
    avg(c.score) as avg_comment_score,
    avg(length(c.text)) as avg_comment_len,
    avg( (length(regexp_replace(c.text, '[^!?]', '', 'g'))::numeric) / nullif(length(c.text),0) ) as punct_density
  from comments c
  group by c.postid
),
-- post links (duplicates and related)
link_agg as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links
  from postlinks pl
  group by pl.postid
),
-- badge richness per user
badge_stats as (
  select
    b.userid,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as golds,
    sum(case when b.class = 2 then 1 else 0 end) as silvers,
    sum(case when b.class = 3 then 1 else 0 end) as bronzes,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
  from badges b
  group by b.userid
),
-- post history signals for closures and edits
posthistory_signals as (
  select
    ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as last_moderation_evt,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_votes,
    count(*) filter (where ph.posthistorytypeid in (11)) as reopen_votes,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied,
    count(*) filter (where ph.posthistorytypeid in (52)) as selected_hot,
    count(*) filter (where ph.posthistorytypeid in (53)) as removed_hot
  from posthistory ph
  group by ph.postid
),
-- tag popularity percentile for each tag on the site
tag_popularity as (
  select
    t.tagname,
    t.count,
    percent_rank() over (order by t.count) as pop_prank,
    ntile(10) over (order by t.count desc) as pop_decile
  from tags t
),
-- explode question tags and join popularity
question_tag_stats as (
  select
    q.q_id,
    unnest(q.tag_arr) as tagname
  from questions q
),
q_tag_enriched as (
  select
    qts.q_id,
    lower(qts.tagname) as tagname,
    coalesce(tp.count, 0) as tag_count,
    coalesce(tp.pop_prank, 0) as tag_pop_prank,
    coalesce(tp.pop_decile, 10) as tag_pop_decile
  from question_tag_stats qts
  left join tag_popularity tp
    on lower(tp.tagname) = lower(qts.tagname)
),
-- aggregate per question across its tags
q_tag_agg as (
  select
    q_id,
    count(*) as tag_cnt,
    min(tag_pop_decile) as best_tag_decile,
    max(tag_pop_decile) as worst_tag_decile,
    avg(tag_pop_prank) as avg_tag_prank,
    sum(tag_count) as sum_tag_counts
  from q_tag_enriched
  group by q_id
),
-- roll up per question signals from answers and votes/comments
answer_rollup as (
  select
    a.q_id,
    count(*) as answers_total,
    sum(a.is_accepted) as accepted_answers,
    min(a.secs_after_q) filter (where a.is_accepted = 1) as secs_to_accept,
    avg(a.a_score) as avg_answer_score,
    max(a.a_score) as max_answer_score
  from answers a
  group by a.q_id
),
-- construct feature-rich question view
question_enriched as (
  select
    q.q_id,
    q.q_ownerid,
    q.q_created,
    q.q_score,
    q.q_views,
    q.title,
    q.tags,
    qa.tag_cnt,
    qa.best_tag_decile,
    qa.worst_tag_decile,
    qa.avg_tag_prank,
    qa.sum_tag_counts,
    ar.answers_total,
    ar.accepted_answers,
    ar.secs_to_accept,
    ar.avg_answer_score,
    ar.max_answer_score,
    va.upvotes as q_upvotes,
    va.downvotes as q_downvotes,
    va.favorites as q_favorites,
    va.total_votes as q_votes_total,
    la.dup_links,
    la.related_links,
    cf.comment_count as q_comment_count,
    cf.avg_comment_score as q_avg_comment_score,
    cf.avg_comment_len as q_avg_comment_len,
    cf.punct_density as q_punct_density,
    phs.last_moderation_evt,
    phs.close_votes,
    phs.reopen_votes,
    phs.suggested_edits_applied,
    phs.selected_hot,
    phs.removed_hot
  from questions q
  left join q_tag_agg qa on qa.q_id = q.q_id
  left join answer_rollup ar on ar.q_id = q.q_id
  left join vote_agg va on va.postid = q.q_id
  left join link_agg la on la.postid = q.q_id
  left join comment_features cf on cf.postid = q.q_id
  left join posthistory_signals phs on phs.postid = q.q_id
),
-- join user info with question owners
owner_enriched as (
  select
    qu.q_id,
    ru.user_id as owner_id,
    ru.displayname as owner_name,
    ru.reputation as owner_rep,
    ru.creationdate as owner_created,
    ru.location as owner_location,
    ru.websiteurl as owner_website,
    ru.net_votes as owner_net_votes,
    bs.badges_total,
    bs.golds,
    bs.silvers,
    bs.bronzes,
    bs.tag_badges,
    row_number() over (partition by ru.user_id order by qu.q_created desc) as owner_recency_order
  from question_enriched qu
  left join recent_users ru on ru.user_id = qu.q_ownerid
  left join badge_stats bs on bs.userid = ru.user_id
),
-- compute moving averages of question scores per owner
owner_q_windows as (
  select
    oe.*,
    avg(coalesce(qe.q_score,0)) over (partition by oe.owner_id order by qe.q_created rows between 4 preceding and current row) as owner_score_ma5,
    count(*) over (partition by oe.owner_id) as owner_q_count
  from owner_enriched oe
  join question_enriched qe on qe.q_id = oe.q_id
),
-- filter interesting questions via complex predicate
interesting_questions as (
  select
    oqw.*,
    qe.q_created,
    qe.q_score,
    qe.q_views,
    qe.title,
    qe.tags,
    qe.answers_total,
    qe.accepted_answers,
    qe.secs_to_accept,
    qe.q_upvotes,
    qe.q_downvotes,
    qe.q_favorites,
    qe.q_votes_total,
    qe.q_comment_count,
    qe.q_avg_comment_score,
    qe.q_avg_comment_len,
    qe.q_punct_density,
    qe.best_tag_decile,
    qe.worst_tag_decile,
    qe.avg_tag_prank,
    qe.sum_tag_counts,
    qe.dup_links,
    qe.related_links,
    qe.close_votes,
    qe.reopen_votes,
    qe.suggested_edits_applied,
    qe.selected_hot,
    qe.removed_hot,
    -- complexity score blending multiple signals
    (
      coalesce(qe.q_score,0) * 2
      + coalesce(qe.q_upvotes,0)
      - coalesce(qe.q_downvotes,0) * 2
      + ln(greatest(qe.q_views,1))
      + coalesce(qe.q_comment_count,0) * 0.5
      + coalesce(qe.q_favorites,0) * 1.5
      + case when qe.accepted_answers > 0 then 3 else 0 end
      + coalesce(10 - qe.best_tag_decile, 0)
      - coalesce(qe.dup_links,0)
    )::numeric(18,4) as complexity_score
  from owner_q_windows oqw
  join question_enriched qe on qe.q_id = oqw.q_id
  where
    -- blend of conditions
    coalesce(qe.q_views,0) > 0
    and (
      (qe.q_score >= 5 and coalesce(qe.q_views,0) >= 1000)
      or (qe.accepted_answers = 1 and coalesce(qe.secs_to_accept, 86400) < 86400*7)
      or (qe.selected_hot > 0)
      or (qe.q_votes_total >= 10 and qe.q_comment_count >= 3)
    )
    and (oqw.owner_rep is null or oqw.owner_rep >= 100)
),
-- top N per owner using window functions
ranked_per_owner as (
  select
    iq.*,
    dense_rank() over (partition by iq.owner_id order by iq.complexity_score desc, iq.q_created desc) as rnk_owner
  from interesting_questions iq
),
-- derive global ranks and quartiles
global_ranked as (
  select
    rpo.*,
    row_number() over (order by complexity_score desc, q_created desc) as global_rownum,
    cume_dist() over (order by complexity_score desc) as global_cumedist,
    ntile(4) over (order by complexity_score desc) as complexity_quartile
  from ranked_per_owner rpo
),
-- construct search-friendly snippets and normalized tags
final_prep as (
  select
    gr.*,
    coalesce(nullif(trim(regexp_replace(lower(coalesce(title,'')), '\s+', ' ', 'g')), ''), '(untitled)') as norm_title,
    coalesce(nullif(trim(regexp_replace(coalesce(tags,''), '\s+', '', 'g')), ''), '<none>') as norm_tags,
    substring(coalesce(title,''), 1, 120) || case when length(coalesce(title,'')) > 120 then '…' else '' end as title_snippet
  from global_ranked gr
)
select
  fp.q_id,
  fp.owner_id,
  fp.owner_name,
  fp.owner_rep,
  fp.badges_total,
  fp.golds,
  fp.silvers,
  fp.bronzes,
  fp.tag_badges,
  fp.owner_score_ma5,
  fp.owner_q_count,
  fp.q_created,
  fp.q_score,
  fp.q_views,
  fp.answers_total,
  fp.accepted_answers,
  fp.secs_to_accept,
  fp.q_upvotes,
  fp.q_downvotes,
  fp.q_favorites,
  fp.q_votes_total,
  fp.q_comment_count,
  fp.q_avg_comment_score,
  fp.q_avg_comment_len,
  fp.q_punct_density,
  fp.best_tag_decile,
  fp.worst_tag_decile,
  fp.avg_tag_prank,
  fp.sum_tag_counts,
  fp.dup_links,
  fp.related_links,
  fp.close_votes,
  fp.reopen_votes,
  fp.suggested_edits_applied,
  fp.selected_hot,
  fp.removed_hot,
  fp.complexity_score,
  fp.rnk_owner,
  fp.global_rownum,
  fp.global_cumedist,
  fp.complexity_quartile,
  fp.norm_title,
  fp.norm_tags,
  fp.title_snippet,
  -- correlated subqueries for extra signals
  coalesce((
    select max(a2.a_score)
    from answers a2
    where a2.q_id = fp.q_id
  ), 0) as corr_max_answer_score,
  coalesce((
    select count(*) from postlinks pl2
    where pl2.relatedpostid = fp.q_id and pl2.linktypeid = 1
  ), 0) as corr_linked_from_count
from final_prep fp
where
  (fp.rnk_owner <= 5 or fp.complexity_quartile = 1)
  and coalesce(fp.owner_name, '') not ilike '%community%'
order by fp.complexity_quartile, fp.complexity_score desc, fp.q_created desc
limit 500;