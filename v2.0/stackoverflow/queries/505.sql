with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
tagged_questions as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') as tag_array
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '730 days' from posts where posttypeid = 1)
),
exploded_tags as (
    select
        tq.question_id,
        tq.owneruserid,
        tq.creationdate,
        tq.score,
        tq.viewcount,
        tq.title,
        lower(element) as tagname
    from tagged_questions tq,
         lateral (
           select unnest(tq.tag_array) as element
         ) ua
),
tag_meta as (
    select
        et.*,
        t.count as global_tag_count,
        t.ismoderatoronly,
        t.isrequired
    from exploded_tags et
    left join tags t on lower(t.tagname) = et.tagname
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner_id,
        a.creationdate as answer_creationdate,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
agg_qna as (
    select
        tm.question_id,
        tm.owneruserid as asker_id,
        min(tm.creationdate) as question_date,
        max(tm.score) filter (where tm.score is not null) as question_score,
        max(tm.viewcount) filter (where tm.viewcount is not null) as question_views,
        count(distinct tm.tagname) as distinct_tags,
        sum(case when tm.ismoderatoronly = true then 1 else 0 end) as moderator_only_tags,
        sum(case when tm.isrequired = true then 1 else 0 end) as required_tags,
        coalesce(sum(tm.global_tag_count),0) as sum_global_tag_popularity,
        count(distinct a.answer_id) as answer_count,
        max(a.answer_score) as top_answer_score,
        min(a.answer_creationdate) as first_answer_time,
        max(case when p.acceptedanswerid is not null then 1 else 0 end) as has_accepted_answer
    from tag_meta tm
    left join answers a on a.question_id = tm.question_id
    left join posts p on p.id = tm.question_id
    group by tm.question_id, tm.owneruserid
),
comment_engagement as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        sum(c.score) as comment_score_sum,
        avg(c.score) as comment_score_avg,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) as total_votes,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
close_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as plain_links,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
recent_activity as (
    select
        p.id as post_id,
        p.lastactivitydate,
        p.lasteditdate,
        p.closeddate,
        p.communityowneddate
    from posts p
),
user_activity_window as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.views,
        u.upvotes,
        u.downvotes,
        u.creationdate,
        u.lastaccessdate,
        row_number() over (order by u.reputation desc, u.id) as rep_rank,
        dense_rank() over (order by u.upvotes - u.downvotes desc) as net_vote_rank,
        lag(u.lastaccessdate) over (order by u.id) as prev_access,
        lead(u.lastaccessdate) over (order by u.id) as next_access
    from users u
),
question_quality as (
    select
        a.question_id,
        a.asker_id,
        a.question_date,
        a.question_score,
        a.question_views,
        a.distinct_tags,
        a.moderator_only_tags,
        a.required_tags,
        a.sum_global_tag_popularity,
        a.answer_count,
        a.top_answer_score,
        a.first_answer_time,
        a.has_accepted_answer,
        ce.close_events,
        ce.last_closed_at,
        ce.last_reopened_at,
        ce.last_close_reason_id,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(va.total_votes,0) as total_votes,
        coalesce(ce.close_events,0) as close_cnt,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.plain_links,0) as plain_links,
        cm.comment_count,
        cm.comment_score_sum,
        cm.comment_score_avg,
        ra.lastactivitydate,
        ra.lasteditdate,
        ra.closeddate,
        ra.communityowneddate
    from agg_qna a
    left join comment_engagement cm on cm.post_id = a.question_id
    left join vote_agg va on va.postid = a.question_id
    left join close_events ce on ce.postid = a.question_id
    left join dup_links dl on dl.question_id = a.question_id
    left join recent_activity ra on ra.post_id = a.question_id
),
scored_questions as (
    select
        qq.*,
        (
            coalesce(qq.question_score, 0) * 2
            + coalesce(qq.upvotes, 0) * 1.5
            - coalesce(qq.downvotes, 0) * 2
            + case when qq.has_accepted_answer = 1 then 10 else 0 end
            + least(coalesce(qq.answer_count,0), 10) * 1.2
            + ln(greatest(coalesce(qq.question_views,0) + 1, 1)) * 3
            + coalesce(qq.favorites,0) * 2
            + coalesce(qq.bounty_total,0) / 50.0
            - coalesce(qq.close_cnt,0) * 5
            - coalesce(qq.duplicate_links,0) * 4
            + coalesce(qq.plain_links,0) * 0.2
            + coalesce(qq.comment_score_sum,0) * 0.5
            + coalesce(qq.comment_count,0) * 0.1
            + case when qq.moderator_only_tags > 0 then -3 else 0 end
            + case when qq.required_tags > 0 then 1 else 0 end
            + least(coalesce(qq.distinct_tags,0), 5) * 0.5
        ) as quality_score,
        extract(epoch from (timestamp '2024-10-01 12:34:56' - coalesce(qq.question_date, timestamp '2024-10-01 12:34:56'))) / 86400.0 as age_days
    from question_quality qq
),
asker_profile as (
    select
        uaw.user_id,
        uaw.displayname,
        uaw.reputation,
        uaw.views,
        uaw.upvotes,
        uaw.downvotes,
        uaw.rep_rank,
        uaw.net_vote_rank,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.tag_badges,
        ub.last_badge_date
    from user_activity_window uaw
    left join user_badges ub on ub.userid = uaw.user_id
),
final_rank as (
    select
        sq.question_id,
        sq.asker_id,
        ap.displayname as asker_name,
        ap.reputation as asker_reputation,
        ap.total_badges,
        ap.gold_badges,
        ap.silver_badges,
        ap.bronze_badges,
        sq.quality_score,
        sq.age_days,
        (
            sq.quality_score
            + ln(greatest(coalesce(ap.reputation,0), 1)) * 0.7
            + coalesce(ap.total_badges,0) * 0.2
        ) as normalized_score,
        row_number() over (
            order by
                (sq.quality_score + ln(greatest(coalesce(ap.reputation,0), 1)) * 0.7 + coalesce(ap.total_badges,0) * 0.2) desc,
                sq.question_id
        ) as overall_rank
    from scored_questions sq
    left join asker_profile ap on ap.user_id = sq.asker_id
)
select
    fr.overall_rank,
    fr.question_id,
    fr.asker_id,
    coalesce(fr.asker_name, '(unknown)') as asker_name,
    coalesce(fr.asker_reputation, 0) as asker_reputation,
    coalesce(fr.total_badges, 0) as total_badges,
    coalesce(fr.gold_badges, 0) as gold_badges,
    coalesce(fr.silver_badges, 0) as silver_badges,
    coalesce(fr.bronze_badges, 0) as bronze_badges,
    round(fr.normalized_score, 3) as normalized_score,
    round(fr.age_days, 2) as age_days,
    case
        when fr.normalized_score >= (
            select percentile_disc(0.9) within group (order by normalized_score) from final_rank
        ) then 'Top 10%'
        when fr.normalized_score >= (
            select percentile_disc(0.75) within group (order by normalized_score) from final_rank
        ) then 'Top 25%'
        when fr.normalized_score >= (
            select avg(normalized_score) from final_rank
        ) then 'Above Avg'
        else 'Below Avg'
    end as tier,
    (select count(*) from answers a where a.question_id = fr.question_id and a.answer_score > 0) as pos_answer_cnt,
    (select count(*) from comments c where c.postid = fr.question_id and c.score > 1) as high_score_comments,
    (select count(*) from postlinks pl where pl.postid = fr.question_id and pl.linktypeid = 3) as dup_markers
from final_rank fr
where fr.overall_rank <= 200
order by fr.overall_rank;