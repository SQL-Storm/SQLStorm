-- {"query": "131.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2995} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.favoritecount,
           p.closeddate,
           p.communityowneddate
    from posts p
    where p.posttypeid = 1
),
answers as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid as answerer_id,
           a.creationdate as answer_created,
           a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
first_answer_per_q as (
    select a.question_id,
           min(a.answer_created) as first_answer_time
    from answers a
    group by a.question_id
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           max(case when v.votetypeid in (8,9) then v.bountyamount else null end) as max_bounty,
           count(*) as total_votes,
           min(v.creationdate) as first_vote_at,
           max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
comment_stats as (
    select c.postid,
           count(*) as comment_count,
           sum(c.score) as comment_score_sum,
           max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
tag_expansion as (
    select p.id as post_id,
           unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from question_posts p
    where p.tags is not null
),
tag_rank as (
    select te.post_id,
           te.tag,
           row_number() over (partition by te.post_id order by coalesce(t.count, 0) desc, te.tag) as tag_pop_rank,
           coalesce(t.count, 0) as site_tag_count
    from tag_expansion te
    left join tags t on lower(t.tagname) = lower(te.tag)
),
top3_tags as (
    select post_id,
           string_agg(tag, ', ' order by tag_pop_rank) as top_tags,
           sum(site_tag_count) as top_tags_total_site_count
    from tag_rank
    where tag_pop_rank <= 3
    group by post_id
),
post_history_flags as (
    select ph.postid,
           max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
           max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
           max(case when ph.posthistorytypeid = 19 then 1 else 0 end) as was_protected,
           max(case when ph.posthistorytypeid = 50 then 1 else 0 end) as was_community_bump,
           max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as was_hot,
           max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot
    from posthistory ph
    group by ph.postid
),
duplicates as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as canonical_post_id,
           min(pl.creationdate) as first_dup_link_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_badge_summary as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
question_metrics as (
    select qp.id as question_id,
           qp.owneruserid as owner_user_id,
           qp.creationdate as question_created,
           qp.score as question_score,
           qp.viewcount,
           qp.answercount,
           qp.favoritecount,
           qp.closeddate,
           qp.communityowneddate,
           fa.first_answer_time,
           extract(epoch from (fa.first_answer_time - qp.creationdate)) as secs_to_first_answer,
           va.upvotes,
           va.downvotes,
           va.favorites as favorite_votes,
           va.max_bounty,
           va.total_votes,
           cs.comment_count,
           cs.comment_score_sum,
           ph.was_closed,
           ph.was_reopened,
           ph.was_protected,
           ph.was_community_bump,
           ph.was_hot,
           ph.removed_hot,
           t3.top_tags,
           t3.top_tags_total_site_count,
           d.canonical_post_id,
           d.first_dup_link_at
    from question_posts qp
    left join first_answer_per_q fa on fa.question_id = qp.id
    left join votes_agg va on va.postid = qp.id
    left join comment_stats cs on cs.postid = qp.id
    left join post_history_flags ph on ph.postid = qp.id
    left join top3_tags t3 on t3.post_id = qp.id
    left join duplicates d on d.dup_post_id = qp.id
),
owner_enriched as (
    select qm.*,
           ru.displayname as owner_name,
           ru.reputation as owner_rep,
           ru.cohort_month,
           coalesce(ru.location, 'Unknown') as owner_location,
           ubs.badge_count,
           ubs.gold_count,
           ubs.silver_count,
           ubs.bronze_count,
           ubs.last_badge_at
    from question_metrics qm
    left join recent_users ru on ru.user_id = qm.owner_user_id
    left join user_badge_summary ubs on ubs.userid = qm.owner_user_id
),
activity_windows as (
    select oe.*,
           count(*) filter (where answerer_id is not null) over (partition by oe.question_id) as answer_count_windowed,
           max(answer_created) over (partition by oe.question_id) as last_answer_at,
           min(answer_created) over (partition by oe.question_id) as first_answer_at_windowed
    from owner_enriched oe
    left join answers a on a.question_id = oe.question_id
),
score_rankings as (
    select aw.*,
           row_number() over (partition by date_trunc('month', aw.question_created), coalesce(aw.top_tags, 'none') order by coalesce(aw.question_score, -2147483648) desc, aw.viewcount desc, aw.question_id) as score_rank_in_month_tag,
           ntile(10) over (order by coalesce(aw.question_score, -2147483648)) as score_decile_global,
           dense_rank() over (order by coalesce(aw.viewcount, -1) desc) as view_dense_rank_global
    from activity_windows aw
),
canonical_join as (
    select s.*,
           c.title as canonical_title,
           c.score as canonical_score,
           c.viewcount as canonical_views
    from score_rankings s
    left join posts c on c.id = s.canonical_post_id
),
final_set as (
    select
        s.question_id,
        s.owner_user_id,
        s.owner_name,
        s.owner_rep,
        s.owner_location,
        s.cohort_month,
        s.question_created,
        s.question_score,
        s.viewcount,
        s.answercount,
        s.favoritecount,
        s.closeddate,
        s.communityowneddate,
        s.first_answer_time,
        s.secs_to_first_answer,
        s.upvotes,
        s.downvotes,
        s.favorite_votes,
        s.max_bounty,
        s.total_votes,
        s.comment_count,
        s.comment_score_sum,
        s.was_closed,
        s.was_reopened,
        s.was_protected,
        s.was_community_bump,
        s.was_hot,
        s.removed_hot,
        s.top_tags,
        s.top_tags_total_site_count,
        s.canonical_post_id,
        s.first_dup_link_at,
        s.answer_count_windowed,
        s.last_answer_at,
        s.first_answer_at_windowed,
        s.score_rank_in_month_tag,
        s.score_decile_global,
        s.view_dense_rank_global,
        s.badge_count,
        s.gold_count,
        s.silver_count,
        s.bronze_count,
        s.last_badge_at,
        coalesce(nullif(trim(s.canonical_title), ''), '[no canonical]') as canonical_title,
        s.canonical_score,
        s.canonical_views
    from canonical_join s
    where coalesce(s.question_score, 0) + coalesce(s.upvotes, 0) - coalesce(s.downvotes, 0) >= 0
),
-- introduce a set operator branch to stress planners
union_branch as (
    select * from final_set
    union all
    select
        fs.question_id,
        fs.owner_user_id,
        fs.owner_name,
        fs.owner_rep,
        fs.owner_location,
        fs.cohort_month,
        fs.question_created,
        fs.question_score,
        fs.viewcount,
        fs.answercount,
        fs.favoritecount,
        fs.closeddate,
        fs.communityowneddate,
        fs.first_answer_time,
        fs.secs_to_first_answer,
        fs.upvotes,
        fs.downvotes,
        fs.favorite_votes,
        fs.max_bounty,
        fs.total_votes,
        fs.comment_count,
        fs.comment_score_sum,
        fs.was_closed,
        fs.was_reopened,
        fs.was_protected,
        fs.was_community_bump,
        fs.was_hot,
        fs.removed_hot,
        fs.top_tags,
        fs.top_tags_total_site_count,
        fs.canonical_post_id,
        fs.first_dup_link_at,
        fs.answer_count_windowed,
        fs.last_answer_at,
        fs.first_answer_at_windowed,
        fs.score_rank_in_month_tag,
        fs.score_decile_global,
        fs.view_dense_rank_global,
        fs.badge_count,
        fs.gold_count,
        fs.silver_count,
        fs.bronze_count,
        fs.last_badge_at,
        fs.canonical_title,
        fs.canonical_score,
        fs.canonical_views
    from final_set fs
    where fs.was_hot = 1
),
rank_union as (
    select ub.*,
           row_number() over (partition by ub.question_id order by (case when ub.was_hot = 1 then 0 else 1 end), ub.score_rank_in_month_tag) as pick_rank
    from union_branch ub
)
select
    ru.question_id,
    ru.owner_user_id,
    ru.owner_name,
    ru.owner_rep,
    ru.owner_location,
    ru.cohort_month,
    ru.question_created,
    ru.question_score,
    ru.viewcount,
    ru.answercount,
    ru.favoritecount,
    ru.closeddate,
    ru.communityowneddate,
    ru.first_answer_time,
    ru.secs_to_first_answer,
    ru.upvotes,
    ru.downvotes,
    ru.favorite_votes,
    ru.max_bounty,
    ru.total_votes,
    ru.comment_count,
    ru.comment_score_sum,
    ru.was_closed,
    ru.was_reopened,
    ru.was_protected,
    ru.was_community_bump,
    ru.was_hot,
    ru.removed_hot,
    ru.top_tags,
    ru.top_tags_total_site_count,
    ru.canonical_post_id,
    ru.canonical_title,
    ru.canonical_score,
    ru.canonical_views,
    ru.first_dup_link_at,
    ru.answer_count_windowed,
    ru.last_answer_at,
    ru.first_answer_at_windowed,
    ru.score_rank_in_month_tag,
    ru.score_decile_global,
    ru.view_dense_rank_global,
    ru.badge_count,
    ru.gold_count,
    ru.silver_count,
    ru.bronze_count,
    ru.last_badge_at,
    -- complicated predicate-derived classification
    case
        when ru.was_closed = 1 and ru.was_reopened = 1 then 'reopened'
        when ru.was_closed = 1 then 'closed'
        when ru.removed_hot = 1 then 'cooled'
        when ru.was_hot = 1 then 'hot'
        when coalesce(ru.answercount, 0) = 0 and ru.viewcount > 0 then 'unanswered'
        else 'normal'
    end as lifecycle_state,
    -- string expression with null/empty logic
    regexp_replace(coalesce(ru.top_tags, '[untagged]') || ' | ' || coalesce(ru.owner_location, 'unknown'), '\s+', ' ', 'g') as tags_location_blob
from rank_union ru
where ru.pick_rank = 1
  and (
    ru.owner_rep is null
    or ru.owner_rep >= (
        select percentile_disc(0.75) within group (order by reputation)
        from users
    )
  )
  and (
    ru.top_tags is null
    or position('sql' in lower(ru.top_tags)) > 0
    or position('postgres' in lower(ru.top_tags)) > 0
  )
order by
    ru.score_decile_global asc,
    ru.view_dense_rank_global asc,
    ru.question_created desc
limit 500;