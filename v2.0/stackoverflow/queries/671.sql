with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (
        select date_trunc('month', max(creationdate)) - interval '6 months'
        from users
    )
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as questions,
        count(case when p.posttypeid = 2 then 1 end) as answers,
        sum(greatest(p.score, 0)) as nonneg_score_sum,
        sum(coalesce(p.viewcount, 0)) as views_sum,
        avg(nullif(p.commentcount, 0)) as avg_commentcount_nonzero,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
user_votes as (
    select
        v.userid as user_id,
        count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
        count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
        count(case when v.votetypeid in (8,9) then 1 end) as bounties_events,
        coalesce(sum(case when v.votetypeid in (8,9) then v.bountyamount else 0 end), 0) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(case when b.class = 1 then 1 end) as gold_badges,
        count(case when b.class = 2 then 1 end) as silver_badges,
        count(case when b.class = 3 then 1 end) as bronze_badges,
        count(case when b.tagbased = true then 1 end) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_stats as (
    select
        p.owneruserid as user_id,
        count(*) as q_count,
        count(case when p.acceptedanswerid is not null then 1 end) as q_with_accepted,
        avg(nullif(p.answercount,0)) as avg_answers_when_any,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) as median_q_views
    from posts p
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid
),
answer_stats as (
    select
        a.owneruserid as user_id,
        count(*) as a_count,
        count(case when exists (
            select 1
            from posts q
            where q.id = a.parentid and q.acceptedanswerid = a.id
        ) then 1 end) as a_marked_accepted,
        avg(coalesce(a.score,0)) as avg_answer_score
    from posts a
    where a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
closure_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        count(*) as close_events
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
question_quality as (
    select
        q.id as post_id,
        q.owneruserid as user_id,
        q.score,
        q.viewcount,
        q.answercount,
        q.creationdate,
        q.closeddate,
        case
            when q.closeddate is not null then 'Closed'
            when q.score >= 10 and coalesce(q.viewcount,0) >= 1000 then 'Hot'
            when q.score < 0 then 'Controversial'
            else 'Normal'
        end as quality_bucket,
        coalesce(c.close_events, 0) as close_events,
        (case when exists (select 1 from dup_links d where d.dup_post_id = q.id) then true else false end) as is_marked_duplicate
    from posts q
    left join closure_events c on c.postid = q.id
    where q.posttypeid = 1 and q.owneruserid is not null
),
tag_exploded as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name
    from posts p
    where p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
),
user_top_tags as (
    select
        q.owneruserid as user_id,
        t.tag_name,
        count(*) as tag_q_count,
        sum(q.score) as tag_q_score,
        row_number() over (partition by q.owneruserid order by count(*) desc, sum(q.score) desc, min(q.id)) as tag_rank
    from posts q
    join tag_exploded t on t.post_id = q.id
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid, t.tag_name
),
hot_network_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_hot_date,
        count(*) as times_hot
    from posthistory ph
    where ph.posthistorytypeid in (52,53)
    group by ph.postid
),
user_recent_comments as (
    select
        c.userid as user_id,
        count(*) as comment_count_90d,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count_90d,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
      and c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    group by c.userid
),
activity_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created,
        ru.location,
        ru.websiteurl,
        coalesce(ua.questions,0) as questions,
        coalesce(ua.answers,0) as answers,
        coalesce(ua.nonneg_score_sum,0) as nonneg_score_sum,
        coalesce(ua.views_sum,0) as views_sum,
        ua.avg_commentcount_nonzero,
        ua.last_activity,
        coalesce(uv.upvotes_cast,0) as upvotes_cast,
        coalesce(uv.downvotes_cast,0) as downvotes_cast,
        coalesce(uv.bounties_events,0) as bounties_events,
        coalesce(uv.bounty_amount_total,0) as bounty_amount_total,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        ub.last_badge_date,
        coalesce(qs.q_count,0) as q_count,
        coalesce(qs.q_with_accepted,0) as q_with_accepted,
        qs.avg_answers_when_any,
        qs.median_q_views,
        coalesce(as2.a_count,0) as a_count,
        coalesce(as2.a_marked_accepted,0) as a_marked_accepted,
        as2.avg_answer_score,
        tt.tag_name as top_tag,
        coalesce(tt.tag_q_count,0) as top_tag_q_count,
        coalesce(tt.tag_q_score,0) as top_tag_q_score
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_votes uv on uv.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join question_stats qs on qs.user_id = ru.user_id
    left join answer_stats as2 on as2.user_id = ru.user_id
    left join lateral (
        select tag_name, tag_q_count, tag_q_score
        from user_top_tags utt
        where utt.user_id = ru.user_id and utt.tag_rank = 1
        order by tag_q_count desc, tag_q_score desc
        limit 1
    ) tt on true
),
post_engagement as (
    select
        p.owneruserid as user_id,
        count(case when qq.quality_bucket = 'Hot' then 1 end) as hot_questions,
        count(case when qq.is_marked_duplicate = true then 1 end) as duplicates_marked,
        count(case when qq.quality_bucket = 'Controversial' then 1 end) as controversial_questions,
        count(case when hn.times_hot > 0 then 1 end) as hot_network_appearances,
        avg(coalesce(p.viewcount,0)) as avg_post_views,
        stddev_pop(coalesce(p.score,0)) as score_stddev
    from posts p
    left join question_quality qq on qq.post_id = p.id
    left join hot_network_events hn on hn.postid = p.id
    where p.owneruserid is not null
      and p.posttypeid in (1,2)
    group by p.owneruserid
),
ranked_users as (
    select
        ar.user_id,
        ar.displayname,
        ar.reputation,
        ar.user_created,
        ar.location,
        ar.websiteurl,
        ar.questions,
        ar.answers,
        ar.nonneg_score_sum,
        ar.views_sum,
        ar.avg_commentcount_nonzero,
        ar.last_activity,
        ar.upvotes_cast,
        ar.downvotes_cast,
        ar.bounties_events,
        ar.bounty_amount_total,
        ar.total_badges,
        ar.gold_badges,
        ar.silver_badges,
        ar.bronze_badges,
        ar.tag_badges,
        ar.last_badge_date,
        ar.q_count,
        ar.q_with_accepted,
        ar.avg_answers_when_any,
        ar.median_q_views,
        ar.a_count,
        ar.a_marked_accepted,
        ar.avg_answer_score,
        ar.top_tag,
        ar.top_tag_q_count,
        ar.top_tag_q_score,
        pe.hot_questions,
        pe.duplicates_marked,
        pe.controversial_questions,
        pe.hot_network_appearances,
        pe.avg_post_views,
        pe.score_stddev,
        coalesce(urc.comment_count_90d,0) as comment_count_90d,
        coalesce(urc.pos_comment_count_90d,0) as pos_comment_count_90d,
        urc.last_comment_date,
        (
            0.4 * ln(1 + greatest(ar.answers,0)) +
            0.3 * ln(1 + greatest(ar.questions,0)) +
            0.2 * ln(1 + greatest(ar.nonneg_score_sum,0)) +
            0.15 * ln(1 + greatest(ar.views_sum,0)) +
            0.1 * ln(1 + greatest(ar.total_badges,0)) +
            0.25 * ln(1 + greatest(coalesce(pe.hot_questions,0),0)) +
            0.05 * ln(1 + greatest(coalesce(ar.bounty_amount_total,0),0)) -
            0.1 * ln(1 + greatest(coalesce(ar.downvotes_cast,0),0))
        ) as activity_score
    from activity_rollup ar
    left join post_engagement pe on pe.user_id = ar.user_id
    left join user_recent_comments urc on urc.user_id = ar.user_id
),
dedup as (
    select distinct on (user_id)
        *
    from ranked_users
    order by user_id, last_activity desc nulls last
),
final_rank as (
    select
        d.*,
        dense_rank() over (
            order by
                activity_score desc nulls last,
                reputation desc,
                coalesce(a_count,0) + coalesce(q_count,0) desc,
                user_id desc
        ) as activity_rank,
        percent_rank() over (order by activity_score) as activity_percentile,
        ntile(10) over (order by activity_score desc nulls last) as activity_decile
    from dedup d
)
select
    fr.user_id,
    fr.displayname,
    fr.reputation,
    fr.location,
    fr.websiteurl,
    fr.user_created,
    fr.last_activity,
    fr.questions,
    fr.answers,
    fr.q_with_accepted,
    fr.a_marked_accepted,
    fr.avg_answers_when_any,
    fr.avg_answer_score,
    fr.median_q_views,
    fr.upvotes_cast,
    fr.downvotes_cast,
    fr.bounties_events,
    fr.bounty_amount_total,
    fr.total_badges,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.tag_badges,
    fr.last_badge_date,
    fr.top_tag,
    fr.top_tag_q_count,
    fr.top_tag_q_score,
    fr.hot_questions,
    fr.duplicates_marked,
    fr.controversial_questions,
    fr.hot_network_appearances,
    fr.avg_post_views,
    fr.score_stddev,
    fr.comment_count_90d,
    fr.pos_comment_count_90d,
    fr.last_comment_date,
    fr.activity_score,
    fr.activity_rank,
    fr.activity_percentile,
    fr.activity_decile
from final_rank fr
where
    (
        fr.activity_decile <= 3
        or fr.reputation >= (
            select percentile_cont(0.9) within group (order by reputation)
            from users
        )
    )
    and (
        fr.top_tag is null
        or not (
            fr.top_tag ilike 'test%' or fr.top_tag ilike 'meta%' or fr.top_tag ilike 'discussion%'
        )
    )
    and (
        fr.location is null
        or fr.location ilike '%united%'
        or fr.location ~ '(^|,|\\s)(us|uk|de|in|ca)(,|\\s|$)'
        or lower(fr.location) like '% us%' or lower(fr.location) like 'us,%' or lower(fr.location) like '% uk%' or lower(fr.location) like 'uk,%' or lower(fr.location) like '% de%' or lower(fr.location) like 'de,%' or lower(fr.location) like '% in%' or lower(fr.location) like 'in,%' or lower(fr.location) like '% ca%' or lower(fr.location) like 'ca,%'
    )
order by fr.activity_rank, fr.user_id
limit 200;