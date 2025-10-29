-- {"query": "571.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2876}
with recursive latest_titles as (
    select p.id as post_id,
           p.title,
           p.creationdate,
           p.owneruserid,
           row_number() over (partition by p.id order by ph.creationdate desc nulls last) as rn
    from posts p
    left join posthistory ph
      on ph.postid = p.id
     and ph.posthistorytypeid in (1,4,7)
),
top_title as (
    select post_id,
           coalesce(
              nullif(trim(title), ''),
              '(untitled)'
           ) as latest_title
    from latest_titles
    where rn = 1
),
user_badge_agg as (
    select u.id as user_id,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from users u
    left join badges b
      on b.userid = u.id
    group by u.id
),
question_core as (
    select q.id,
           q.owneruserid,
           q.creationdate,
           q.score,
           q.viewcount,
           q.favoritecount,
           q.answercount,
           q.tags,
           q.acceptedanswerid,
           q.closeddate,
           q.communityowneddate,
           q.lastactivitydate
    from posts q
    where q.posttypeid = 1
),
answers as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid as answer_owner_id,
           a.score as answer_score,
           a.creationdate as answer_date,
           row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn_by_score,
           row_number() over (partition by a.parentid order by a.creationdate asc) as rn_by_time
    from posts a
    where a.posttypeid = 2
),
votes_agg as (
    select v.postid,
           count(case when v.votetypeid = 2 then 1 end) as upvotes,
           count(case when v.votetypeid = 3 then 1 end) as downvotes,
           count(case when v.votetypeid = 5 then 1 end) as favorites_legacy,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
comment_stats as (
    select c.postid,
           count(*) as comment_count,
           max(c.score) as max_comment_score,
           avg(case when c.score is not null then c.score end) as avg_comment_score,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
postlinks_agg as (
    select pl.postid,
           count(case when pl.linktypeid = 1 then 1 end) as linked_count,
           count(case when pl.linktypeid = 3 then 1 end) as duplicate_count,
           count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
    from postlinks pl
    group by pl.postid
),
close_reasons as (
    select ph.postid,
           max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_comment_raw,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
user_activity as (
    select u.id as user_id,
           u.reputation,
           u.creationdate as user_created,
           u.lastaccessdate,
           u.location,
           u.websiteurl,
           ua.badge_count,
           ua.gold_count,
           ua.silver_count,
           ua.bronze_count,
           ua.first_badge_date,
           ua.last_badge_date,
           coalesce(u.upvotes,0) - coalesce(u.downvotes,0) as vote_delta
    from users u
    left join user_badge_agg ua on ua.user_id = u.id
),
tag_split as (
    select qc.id as post_id,
           unnest(string_to_array(substring(qc.tags, 2, length(qc.tags)-2), '><')) as tag
    from question_core qc
    where qc.tags is not null
),
tag_rank as (
    select post_id,
           tag,
           row_number() over (partition by post_id order by length(tag) desc, tag asc) as tag_len_rank,
           dense_rank() over (partition by post_id order by tag asc) as tag_alpha_rank
    from tag_split
),
chosen_tags as (
    select post_id,
           string_agg(tag, ';' order by tag) as tags_alpha,
           string_agg(tag, ';' order by length(tag) desc, tag asc) as tags_by_len,
           max(case when tag_len_rank = 1 then tag end) as longest_tag,
           max(case when tag_alpha_rank = 1 then tag end) as first_alpha_tag
    from tag_rank
    group by post_id
),
answer_picks as (
    select a.question_id,
           max(case when a.rn_by_score = 1 then a.answer_id end) as top_scored_answer_id,
           max(case when a.rn_by_time = 1 then a.answer_id end) as first_answer_id
    from answers a
    group by a.question_id
),
accepted_vs_best as (
    select q.id as question_id,
           q.acceptedanswerid,
           ap.top_scored_answer_id,
           ap.first_answer_id,
           case when q.acceptedanswerid is null then 'NO_ACCEPTED'
                when q.acceptedanswerid = ap.top_scored_answer_id then 'ACCEPTED_IS_TOP'
                when q.acceptedanswerid = ap.first_answer_id then 'ACCEPTED_IS_FIRST'
                else 'ACCEPTED_OTHER'
           end as accepted_category
    from question_core q
    left join answer_picks ap on ap.question_id = q.id
),
score_buckets as (
    select q.id as question_id,
           case
             when q.score is null then null
             when q.score < -5 then 1
             when q.score >= -5 and q.score < 0 then 1
             when q.score >= 0 and q.score <= 4 then 2
             when q.score >= 5 and q.score <= 9 then 3
             when q.score >= 10 and q.score <= 24 then 4
             when q.score >= 25 and q.score <= 49 then 5
             else 6
           end as score_bucket,
           case
             when q.score is null then 'NULL'
             when q.score < 0 then '<0'
             when q.score between 0 and 4 then '0-4'
             when q.score between 5 and 9 then '5-9'
             when q.score between 10 and 24 then '10-24'
             when q.score between 25 and 49 then '25-49'
             else '50+'
           end as score_range_label
    from question_core q
),
activity_windows as (
    select q.id as question_id,
           q.creationdate,
           q.lastactivitydate,
           extract(epoch from (coalesce(q.lastactivitydate, q.creationdate) - q.creationdate))/3600.0 as hours_active,
           ntile(10) over (order by coalesce(q.viewcount,0) desc nulls last) as view_decile
    from posts q
    where q.posttypeid = 1
),
final_agg as (
    select
        q.id as question_id,
        tt.latest_title,
        coalesce(ct.tags_alpha, '') as tags_alpha,
        coalesce(ct.tags_by_len, '') as tags_by_len,
        ct.longest_tag,
        ct.first_alpha_tag,
        q.creationdate,
        q.score,
        q.viewcount,
        q.favoritecount,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.favorites_legacy,0) as favorites_legacy,
        coalesce(v.bounty_total,0) as bounty_total,
        coalesce(cs.comment_count,0) as comment_count,
        cs.max_comment_score,
        cs.avg_comment_score,
        cs.last_comment_date,
        pl.linked_count,
        pl.duplicate_count,
        pl.distinct_dupe_targets,
        cr.last_close_comment_raw,
        cr.last_close_date,
        avb.accepted_category,
        sb.score_range_label,
        aw.hours_active,
        aw.view_decile,
        u.displayname as owner_display_name,
        ua.reputation as owner_reputation,
        ua.vote_delta as owner_vote_delta,
        ua.badge_count as owner_badges_total,
        ua.gold_count as owner_badges_gold,
        ua.silver_count as owner_badges_silver,
        ua.bronze_count as owner_badges_bronze,
        date_part('day', cast('2024-10-01 12:34:56' as timestamp) - ua.user_created) as user_age_days,
        case
          when q.closeddate is not null and q.communityowneddate is not null then 'CLOSED_AND_WIKI'
          when q.closeddate is not null then 'CLOSED'
          when q.communityowneddate is not null then 'WIKI'
          else 'OPEN'
        end as post_state_flag,
        case when q.viewcount is null or q.viewcount = 0 then null
             else round( (coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) / nullif(q.viewcount,0), 6)
        end as net_votes_per_view,
        case when q.answercount is null or q.answercount = 0 then 0
             else round(coalesce(v.bounty_total,0) / nullif(q.answercount,0), 2)
        end as bounty_per_answer,
        case when cr.last_close_comment_raw ~ '^[0-9]+$'
             then (select crt.name from closereasontypes crt where crt.id = cast(cr.last_close_comment_raw as smallint))
             else null
        end as last_close_reason_name
    from question_core q
    left join top_title tt on tt.post_id = q.id
    left join chosen_tags ct on ct.post_id = q.id
    left join votes_agg v on v.postid = q.id
    left join comment_stats cs on cs.postid = q.id
    left join postlinks_agg pl on pl.postid = q.id
    left join close_reasons cr on cr.postid = q.id
    left join accepted_vs_best avb on avb.question_id = q.id
    left join score_buckets sb on sb.question_id = q.id
    left join activity_windows aw on aw.question_id = q.id
    left join users u on u.id = q.owneruserid
    left join user_activity ua on ua.user_id = q.owneruserid
),
ranked as (
    select
        f.question_id,
        f.latest_title,
        f.tags_alpha,
        f.tags_by_len,
        f.longest_tag,
        f.first_alpha_tag,
        f.creationdate,
        f.score,
        f.viewcount,
        f.favoritecount,
        f.upvotes,
        f.downvotes,
        f.favorites_legacy,
        f.bounty_total,
        f.comment_count,
        f.max_comment_score,
        f.avg_comment_score,
        f.last_comment_date,
        f.linked_count,
        f.duplicate_count,
        f.distinct_dupe_targets,
        f.last_close_comment_raw,
        f.last_close_date,
        f.accepted_category,
        f.score_range_label,
        f.hours_active,
        f.view_decile,
        f.owner_display_name,
        f.owner_reputation,
        f.owner_vote_delta,
        f.owner_badges_total,
        f.owner_badges_gold,
        f.owner_badges_silver,
        f.owner_badges_bronze,
        f.user_age_days,
        f.post_state_flag,
        f.net_votes_per_view,
        f.bounty_per_answer,
        f.last_close_reason_name,
        row_number() over (
            order by
                coalesce(f.viewcount,0) desc,
                coalesce(f.upvotes,0) desc,
                f.creationdate desc
        ) as rownum_global,
        row_number() over (
            partition by f.score_range_label
            order by coalesce(f.net_votes_per_view,0) desc nulls last
        ) as rownum_by_score_bucket,
        rank() over (
            partition by f.post_state_flag
            order by coalesce(f.bounty_total,0) desc, f.creationdate desc
        ) as rank_by_state
    from final_agg f
),
filtered as (
    select r.*
    from ranked r
    where
      (
        (duplicate_count > 0 and accepted_category = 'NO_ACCEPTED')
        or (upvotes - downvotes >= 10 and coalesce(longest_tag,'') <> '')
        or (post_state_flag in ('CLOSED','CLOSED_AND_WIKI') and net_votes_per_view is not null and net_votes_per_view > 0.01)
      )
      and coalesce(viewcount,0) >= 10
      and (owner_reputation is null or owner_reputation >= 100)
      and (
            lower(tags_alpha) like '%sql%' 
         or lower(tags_alpha) like '%postgres%' 
         or lower(tags_alpha) like '%database%'
          )
)
select
    question_id,
    coalesce(latest_title, '(untitled)') as latest_title,
    tags_alpha,
    tags_by_len,
    longest_tag,
    first_alpha_tag,
    creationdate,
    score,
    viewcount,
    favoritecount,
    upvotes,
    downvotes,
    favorites_legacy,
    bounty_total,
    comment_count,
    max_comment_score,
    round(avg_comment_score, 3) as avg_comment_score,
    last_comment_date,
    linked_count,
    duplicate_count,
    distinct_dupe_targets,
    coalesce(last_close_reason_name, 'N/A') as last_close_reason_name,
    last_close_date,
    accepted_category,
    score_range_label,
    hours_active,
    view_decile,
    owner_display_name,
    owner_reputation,
    owner_vote_delta,
    owner_badges_total,
    owner_badges_gold,
    owner_badges_silver,
    owner_badges_bronze,
    user_age_days,
    post_state_flag,
    net_votes_per_view,
    bounty_per_answer,
    rownum_global,
    rownum_by_score_bucket,
    rank_by_state
from filtered
order by
    rownum_by_score_bucket asc,
    rank_by_state asc,
    rownum_global asc
limit 200;