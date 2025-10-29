with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'NA') as websiteurl_clean
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
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
        p.parentid
    from posts p
    where p.posttypeid in (1,2)
),
user_post_stats as (
    select
        ru.user_id,
        count(*) filter (where qa.posttypeid = 1) as question_count,
        count(*) filter (where qa.posttypeid = 2) as answer_count,
        sum(qa.score) as total_post_score,
        cast(avg(qa.score) as numeric(18,4)) as avg_post_score,
        sum(coalesce(qa.viewcount,0)) filter (where qa.posttypeid = 1) as question_views,
        max(qa.creationdate) as last_post_date
    from recent_users ru
    left join q_and_a qa
      on qa.owneruserid = ru.user_id
    group by ru.user_id
),
tag_explode as (
    select
        p.id as question_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.tags like '<%>'
),
top_user_tags as (
    select
        qa.owneruserid as user_id,
        te.tagname,
        count(*) as tag_q_count,
        row_number() over (partition by qa.owneruserid order by count(*) desc, min(qa.creationdate) asc) as rn
    from q_and_a qa
    join tag_explode te
      on te.question_id = qa.id
    where qa.posttypeid = 1
    group by qa.owneruserid, te.tagname
),
accepted_answer_latency as (
    select
        q.owneruserid as asker_id,
        q.id as question_id,
        q.creationdate as question_date,
        a.id as accepted_id,
        a.owneruserid as answerer_id,
        a.creationdate as accepted_date,
        extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
comment_activity as (
    select
        u.id as user_id,
        count(c.id) as comment_count,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_date
    from users u
    left join comments c
      on c.userid = u.id
    group by u.id
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where cast(b.tagbased as integer) = 1) as tag_badges
    from badges b
    group by b.userid
),
vote_rollup as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total,
        min(v.creationdate) as first_vote_date,
        max(v.creationdate) as last_vote_date
    from votes v
    group by v.userid
),
post_vote_impact as (
    select
        p.owneruserid as user_id,
        count(*) filter (where vt.votetypeid = 2) as upvotes_received,
        count(*) filter (where vt.votetypeid = 3) as downvotes_received,
        sum(case when vt.votetypeid = 2 then 1 when vt.votetypeid = 3 then -1 else 0 end) as net_votes_received
    from posts p
    left join votes vt
      on vt.postid = p.id
    group by p.owneruserid
),
closure_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_count,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_count,
        sum(case when ph.posthistorytypeid = 10 then 1 when ph.posthistorytypeid = 11 then -1 else 0 end) as net_closes
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicate_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as canonical_post_id,
        count(*) as dup_links
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_dup_impact as (
    select
        q.owneruserid as user_id,
        count(distinct d.dup_post_id) as questions_marked_duplicate,
        count(distinct d.canonical_post_id) as unique_canonical_refs
    from duplicate_links d
    join posts q on q.id = d.dup_post_id and q.posttypeid = 1
    group by q.owneruserid
),
activity_calendar as (
    select
        u.id as user_id,
        cast(date_trunc('month', p.creationdate) as date) as month_bucket,
        count(*) as posts_in_month,
        sum(p.score) as month_score,
        dense_rank() over (partition by u.id order by date_trunc('month', p.creationdate)) as month_seq
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, date_trunc('month', p.creationdate)
),
user_activity_trends as (
    select
        ac.user_id,
        ac.month_bucket,
        ac.posts_in_month,
        ac.month_score,
        sum(ac.posts_in_month) over (partition by ac.user_id order by ac.month_bucket rows between unbounded preceding and current row) as cum_posts,
        avg(ac.posts_in_month) over (partition by ac.user_id order by ac.month_bucket rows between 2 preceding and current row) as mov_avg_posts_last_3,
        lag(ac.posts_in_month) over (partition by ac.user_id order by ac.month_bucket) as prev_month_posts
    from activity_calendar ac
),
user_quality_score as (
    select
        ru.user_id,
        cast(
            (
                coalesce(ups.avg_post_score,0) * 0.5
                + coalesce(pvi.net_votes_received,0) * 0.3
                + coalesce(br.gold_badges,0) * 5
                + coalesce(br.silver_badges,0) * 2
                + coalesce(br.bronze_badges,0) * 1
                - coalesce(vr.downvotes_cast,0) * 0.2
            ) as numeric(18,4)
        ) as quality_score,
        case when coalesce(ups.answer_count,0) > coalesce(ups.question_count,0) then 'Answerer'
             when coalesce(ups.question_count,0) > coalesce(ups.answer_count,0) then 'Asker'
             else 'Balanced' end as role_profile
    from recent_users ru
    left join user_post_stats ups on ups.user_id = ru.user_id
    left join post_vote_impact pvi on pvi.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join vote_rollup vr on vr.user_id = ru.user_id
),
accepted_latency_by_user as (
    select
        aa.asker_id as user_id,
        avg(case when aa.hours_to_accept between 0 and 24 then aa.hours_to_accept end) as avg_accept_24h,
        avg(case when aa.hours_to_accept > 24 then aa.hours_to_accept end) as avg_accept_after_24h,
        percentile_cont(0.5) within group (order by aa.hours_to_accept) as p50_accept_hours,
        count(*) as accepted_questions
    from accepted_answer_latency aa
    group by aa.asker_id
),
string_features as (
    select
        u.id as user_id,
        lower(coalesce(u.location, 'unknown')) as location_lc,
        coalesce(regexp_replace(lower(coalesce(u.location, 'unknown')), '[^a-z0-9 ]', '', 'g'), 'unknown') as location_norm,
        case when position('remote' in lower(coalesce(u.aboutme, ''))) > 0 then true else false end as mentions_remote,
        length(coalesce(u.displayname, '')) as displayname_len
    from users u
),
power_users as (
    select
        ru.user_id,
        (ru.reputation >= percentile_disc(0.95) within group (order by ru.reputation)) as is_top5pct_reputation
    from recent_users ru
    group by ru.user_id, ru.reputation
),
final_rank as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ups.question_count,
        ups.answer_count,
        ups.total_post_score,
        ups.avg_post_score,
        ups.question_views,
        ups.last_post_date,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score,0) as comment_score,
        ca.last_comment_date,
        coalesce(br.total_badges,0) as total_badges,
        coalesce(br.gold_badges,0) as gold_badges,
        coalesce(br.silver_badges,0) as silver_badges,
        coalesce(br.bronze_badges,0) as bronze_badges,
        coalesce(br.tag_badges,0) as tag_badges,
        coalesce(vr.upvotes_cast,0) as upvotes_cast,
        coalesce(vr.downvotes_cast,0) as downvotes_cast,
        coalesce(vr.bounty_total,0) as bounty_total,
        vr.first_vote_date,
        vr.last_vote_date,
        coalesce(pvi.upvotes_received,0) as upvotes_received,
        coalesce(pvi.downvotes_received,0) as downvotes_received,
        coalesce(pvi.net_votes_received,0) as net_votes_received,
        coalesce(udi.questions_marked_duplicate,0) as questions_marked_duplicate,
        coalesce(udi.unique_canonical_refs,0) as unique_canonical_refs,
        coalesce(ual.avg_accept_24h,0) as avg_accept_24h,
        coalesce(ual.avg_accept_after_24h,0) as avg_accept_after_24h,
        coalesce(ual.p50_accept_hours,0) as p50_accept_hours,
        coalesce(ual.accepted_questions,0) as accepted_questions,
        uqs.quality_score,
        uqs.role_profile,
        sut.tagname as top_tag,
        sfeat.location_lc,
        sfeat.location_norm,
        sfeat.mentions_remote,
        sfeat.displayname_len,
        pu.is_top5pct_reputation,
        rank() over (
            order by
                uqs.quality_score desc,
                coalesce(ups.answer_count,0) desc,
                coalesce(ups.question_count,0) desc,
                coalesce(pvi.net_votes_received,0) desc,
                coalesce(br.total_badges,0) desc
        ) as overall_rank
    from recent_users ru
    left join user_post_stats ups on ups.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join vote_rollup vr on vr.user_id = ru.user_id
    left join post_vote_impact pvi on pvi.user_id = ru.user_id
    left join user_dup_impact udi on udi.user_id = ru.user_id
    left join accepted_latency_by_user ual on ual.user_id = ru.user_id
    left join user_quality_score uqs on uqs.user_id = ru.user_id
    left join power_users pu on pu.user_id = ru.user_id
    left join string_features sfeat on sfeat.user_id = ru.user_id
    left join lateral (
        select tagname
        from top_user_tags tut
        where tut.user_id = ru.user_id
          and tut.rn = 1
        limit 1
    ) sut on true
)
select
    fr.user_id,
    fr.displayname,
    fr.reputation,
    fr.creationdate,
    fr.location,
    fr.question_count,
    fr.answer_count,
    fr.total_post_score,
    fr.avg_post_score,
    fr.question_views,
    fr.last_post_date,
    fr.comment_count,
    fr.comment_score,
    fr.last_comment_date,
    fr.total_badges,
    fr.gold_badges,
    fr.silver_badges,
    fr.bronze_badges,
    fr.tag_badges,
    fr.upvotes_cast,
    fr.downvotes_cast,
    fr.bounty_total,
    fr.first_vote_date,
    fr.last_vote_date,
    fr.upvotes_received,
    fr.downvotes_received,
    fr.net_votes_received,
    fr.questions_marked_duplicate,
    fr.unique_canonical_refs,
    fr.avg_accept_24h,
    fr.avg_accept_after_24h,
    fr.p50_accept_hours,
    fr.accepted_questions,
    fr.quality_score,
    fr.role_profile,
    fr.top_tag,
    fr.location_lc,
    fr.location_norm,
    fr.mentions_remote,
    fr.displayname_len,
    fr.is_top5pct_reputation,
    fr.overall_rank,
    at.month_bucket,
    at.posts_in_month,
    at.month_score,
    at.cum_posts,
    at.mov_avg_posts_last_3,
    at.prev_month_posts,
    case
        when fr.is_top5pct_reputation then 'Elite'
        when fr.quality_score >= (select avg(quality_score) from final_rank) then 'AboveAverage'
        else 'Regular'
    end as cohort,
    case
        when fr.question_count is null and fr.answer_count is null then 'NoPosts'
        when coalesce(fr.answer_count,0) = 0 and coalesce(fr.question_count,0) > 0 then 'QuestionsOnly'
        when coalesce(fr.question_count,0) = 0 and coalesce(fr.answer_count,0) > 0 then 'AnswersOnly'
        else 'Mixed'
    end as posting_style
from final_rank fr
left join user_activity_trends at
  on at.user_id = fr.user_id
where
    (fr.top_tag is null or length(fr.top_tag) between 2 and 35)
    and (
        fr.location_norm is null
        or (fr.location_norm not like '%spam%' and fr.location_norm not like '%bot%')
    )
    and (
        fr.net_votes_received is null
        or fr.net_votes_received >= (
            select coalesce(percentile_disc(0.25) within group (order by net_votes_received), 0)
            from post_vote_impact
        )
    )
    and (
        fr.last_post_date is null
        or fr.last_post_date >= (select max(creationdate) - interval '730 days' from posts)
    )
order by fr.overall_rank, at.month_bucket nulls last
limit 500;