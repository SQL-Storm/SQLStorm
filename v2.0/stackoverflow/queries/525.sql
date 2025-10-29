-- {"query": "525.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3197}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as website_host,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
    from users u
    where u.creationdate >= (select max(creationdate) - interval '5 years' from users)
),
post_enriched as (
    select p.id,
           p.posttypeid,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.commentcount,
           p.favoritecount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.parentid,
           case when p.posttypeid = 1 then 'Question'
                when p.posttypeid = 2 then 'Answer'
                else 'Other' end as posttype_name,
           array_length(string_to_array(coalesce(nullif(substring(p.tags, 2, greatest(length(p.tags)-2,0)), ''), ''), '><'), 1) as tag_count,
           extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - p.creationdate)) / 86400.0 as age_days
    from posts p
    where p.creationdate is not null
),
qna_links as (
    select pl.postid,
           pl.relatedpostid,
           pl.linktypeid,
           lt.name as linktype_name,
           case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
),
votes_rollup as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
           min(v.creationdate) as first_vote_at,
           max(v.creationdate) as last_vote_at,
           count(*) as vote_events
    from votes v
    group by v.postid
),
comments_rollup as (
    select c.postid,
           count(*) as comment_cnt,
           sum(greatest(c.score,0)) as pos_comment_score,
           max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
badge_firsts as (
    select b.userid,
           min(b.date) as first_badge_at,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count
    from badges b
    group by b.userid
),
post_closures as (
    select ph.postid,
           min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
           min(case when ph.posthistorytypeid = 11 then ph.creationdate end) as first_reopened_at,
           sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events,
           sum(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopen_events,
           -- parse numeric close reason when present, standard cast
           min(case when ph.posthistorytypeid = 10 then cast(nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') as integer) end) as any_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
question_core as (
    select pe.*,
           case when pe.posttypeid = 1 then 1 else 0 end as is_question,
           case when pe.posttypeid = 2 then 1 else 0 end as is_answer
    from post_enriched pe
    where pe.posttypeid in (1,2)
),
answers_to_questions as (
    select a.id as answer_id,
           a.parentid as question_id,
           a.owneruserid as answer_owner_id,
           a.score as answer_score,
           a.creationdate as answer_created,
           row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc, a.id) as rn_best_score,
           row_number() over (partition by a.parentid order by a.creationdate asc, a.id) as rn_first_answer,
           count(*) over (partition by a.parentid) as total_answers
    from question_core a
    where a.posttypeid = 2 and a.parentid is not null
),
question_stats as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate as question_created,
           q.score as question_score,
           q.viewcount as question_views,
           q.commentcount as question_comments,
           q.tag_count,
           q.age_days,
           coalesce(vr.upvotes,0) as q_upvotes,
           coalesce(vr.downvotes,0) as q_downvotes,
           coalesce(vr.favorites,0) as q_favorites,
           coalesce(vr.bounty_total,0) as bounty_total,
           coalesce(cr.comment_cnt,0) as q_comment_cnt,
           pc.first_closed_at,
           pc.last_closed_at,
           pc.first_reopened_at,
           pc.close_events,
           pc.reopen_events,
           pc.any_close_reason_id,
           q.acceptedanswerid
    from question_core q
    left join votes_rollup vr on vr.postid = q.id
    left join comments_rollup cr on cr.postid = q.id
    left join post_closures pc on pc.postid = q.id
    where q.posttypeid = 1
),
accepted_answer as (
    select a.question_id,
           a.answer_id,
           a.answer_owner_id,
           a.answer_score,
           a.answer_created
    from answers_to_questions a
    join question_stats qs on qs.acceptedanswerid = a.answer_id
),
best_scored_answer as (
    select a.question_id, a.answer_id, a.answer_owner_id, a.answer_score, a.answer_created
    from answers_to_questions a
    where a.rn_best_score = 1
),
first_answer as (
    select a.question_id, a.answer_id, a.answer_owner_id, a.answer_score, a.answer_created
    from answers_to_questions a
    where a.rn_first_answer = 1
),
dup_map as (
    select q.postid as dup_post_id,
           q.relatedpostid as canonical_post_id
    from qna_links q
    where q.linktypeid = 3
),
tag_explode as (
    select q.id as question_id,
           unnest(string_to_array(coalesce(nullif(substring(q.tags, 2, greatest(length(q.tags)-2,0)), ''), ''), '><')) as tag
    from post_enriched q
    where q.posttypeid = 1 and q.tags is not null
),
tag_density as (
    select te.question_id,
           count(*) as tag_ct,
           sum(case when lower(te.tag) in ('sql','postgresql','mysql') then 1 else 0 end) as sql_related_ct,
           string_agg(te.tag, '|' order by te.tag) as tags_concat
    from tag_explode te
    group by te.question_id
),
user_activity as (
    select u.user_id,
           u.displayname,
           u.reputation,
           u.cohort_month,
           u.website_host,
           coalesce(bf.badge_count,0) as badge_count,
           coalesce(bf.gold_count,0) as gold_count,
           coalesce(bf.silver_count,0) as silver_count,
           coalesce(bf.bronze_count,0) as bronze_count,
           u.rn_newest
    from recent_users u
    left join badge_firsts bf on bf.userid = u.user_id
),
question_owner as (
    select qs.question_id,
           ua.user_id as owner_id,
           ua.displayname as owner_name,
           ua.reputation as owner_rep,
           ua.website_host as owner_host,
           ua.badge_count as owner_badges,
           ua.gold_count as owner_gold
    from question_stats qs
    left join user_activity ua on ua.user_id = qs.asker_id
),
answer_contributors as (
    select distinct on (a.question_id)
           a.question_id,
           ua.user_id as contributor_id,
           ua.displayname as contributor_name,
           ua.reputation as contributor_rep,
           ua.website_host as contributor_host
    from answers_to_questions a
    left join user_activity ua on ua.user_id = a.answer_owner_id
    order by a.question_id, ua.reputation desc nulls last, ua.user_id
),
question_quality as (
    select qs.question_id,
           qs.question_score,
           qs.question_views,
           qs.q_upvotes,
           qs.q_downvotes,
           qs.q_favorites,
           qs.bounty_total,
           coalesce(td.sql_related_ct,0) as sql_related_ct,
           coalesce(td.tag_ct,0) as tag_ct,
           td.tags_concat,
           case
             when qs.question_views >= 100000 then 'ultra'
             when qs.question_views >= 10000 then 'high'
             when qs.question_views >= 1000 then 'medium'
             else 'low'
           end as view_tier,
           (qs.q_upvotes - qs.q_downvotes) as net_votes,
           case when qs.first_closed_at is not null then 1 else 0 end as was_closed,
           case when qs.any_close_reason_id in (101,1) then 'duplicate'
                when qs.any_close_reason_id in (102,2) then 'off-topic'
                when qs.any_close_reason_id in (103,104,105,3,4,7) then 'needs-work'
                when qs.any_close_reason_id is null then 'none'
                else 'other'
           end as close_reason_group
    from question_stats qs
    left join tag_density td on td.question_id = qs.question_id
),
answer_summary as (
    select qs.question_id,
           coalesce(ba.answer_id, fa.answer_id, bsa.answer_id) as chosen_answer_id,
           case
             when qs.acceptedanswerid is not null then 'accepted'
             when bsa.answer_id is not null then 'best_scored'
             when fa.answer_id is not null then 'first'
             else 'none'
           end as answer_pick_strategy,
           coalesce(bsa.answer_score, fa.answer_score, cast(-2147483648 as integer)) as proxy_best_score,
           (select count(*) from answers_to_questions ax where ax.question_id = qs.question_id) as total_answers
    from question_stats qs
    left join accepted_answer ba on ba.question_id = qs.question_id
    left join best_scored_answer bsa on bsa.question_id = qs.question_id
    left join first_answer fa on fa.question_id = qs.question_id
),
final_pre as (
    select
        qs.question_id,
        qo.owner_id,
        coalesce(qo.owner_name, '(unknown)') as owner_name,
        coalesce(qo.owner_rep, 0) as owner_rep,
        coalesce(qo.owner_host, 'unknown') as owner_host,
        coalesce(qo.owner_badges,0) as owner_badges,
        qq.view_tier,
        qq.net_votes,
        qq.question_views,
        qq.q_favorites,
        qq.sql_related_ct,
        qq.tag_ct,
        qq.tags_concat,
        qq.close_reason_group,
        qq.was_closed,
        asu.answer_pick_strategy,
        asu.total_answers,
        coalesce(asu.proxy_best_score, cast(-2147483648 as integer)) as proxy_best_score,
        ac.contributor_id,
        ac.contributor_name,
        ac.contributor_rep,
        ac.contributor_host,
        case when dm.canonical_post_id is not null then 1 else 0 end as is_duplicate,
        dm.canonical_post_id,
        -- windowed ranks for benchmarking
        rank() over (order by qq.net_votes desc nulls last, qq.question_views desc) as r_net_votes,
        dense_rank() over (order by qq.view_tier desc, qq.question_views desc) as r_view_tier,
        row_number() over (partition by qq.close_reason_group order by qq.net_votes desc nulls last) as r_by_close_group,
        -- conditional aggregation via filtered windows
        sum(case when qq.was_closed = 1 then 1 else 0 end) over () as closed_total_all,
        avg(cast(qq.question_views as numeric)) over () as avg_views_all,
        avg(case when qq.was_closed = 0 then cast(qq.question_views as numeric) else null end) over () as avg_views_open_only,
        -- complex predicate score
        ( (coalesce(qo.owner_rep,0) / nullif(1 + qq.tag_ct,0))
            + (case when qq.sql_related_ct > 0 then 5 else 0 end)
            + least(qq.net_votes, 50)
        ) as author_influence_score
    from question_stats qs
    left join question_owner qo on qo.question_id = qs.question_id
    left join question_quality qq on qq.question_id = qs.question_id
    left join answer_summary asu on asu.question_id = qs.question_id
    left join answer_contributors ac on ac.question_id = qs.question_id
    left join dup_map dm on dm.dup_post_id = qs.question_id
    where (qq.view_tier in ('ultra','high') or (qq.net_votes >= 5 and qq.tag_ct >= 2))
      and (qs.first_closed_at is null or qs.first_reopened_at is not null or qq.close_reason_group <> 'off-topic')
      and (coalesce(qo.owner_host, 'unknown') <> 'example.com' or qq.sql_related_ct > 0)
),
-- compute rank of author_influence_score to allow filtering by it
final_with_rank as (
    select fp.*,
           dense_rank() over (order by author_influence_score desc) as author_influence_score_rank
    from final_pre fp
)
select *
from final_with_rank
where
    r_net_votes <= 200
    or (is_duplicate = 1 and r_by_close_group <= 300)
    or (view_tier = 'ultra' and author_influence_score_rank <= 500)
order by
    view_tier desc,
    is_duplicate desc,
    net_votes desc nulls last,
    question_views desc,
    owner_rep desc nulls last,
    question_id asc;