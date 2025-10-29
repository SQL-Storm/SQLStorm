with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.parentid,
        p.acceptedanswerid,
        p.owneruserid,
        p.creationdate,
        p.lastactivitydate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.title,
        p.tags,
        coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname) as owner_name,
        u.reputation,
        u.upvotes,
        u.downvotes
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= (select max(creationdate) - interval '180 days' from posts)
),
user_activity as (
    select
        u.id as user_id,
        count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
        count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(c_cnt.c_cnt,0)) as total_comments_on_posts,
        sum(coalesce(vu.upvotes,0)) as received_upvotes,
        sum(coalesce(vd.downvotes,0)) as received_downvotes,
        max(u.creationdate) as user_creationdate
    from users u
    left join posts p on p.owneruserid = u.id
    left join (
        select postid, count(*) as c_cnt
        from comments
        group by postid
    ) c_cnt on c_cnt.postid = p.id
    left join lateral (
        select count(*) as upvotes
        from votes v
        where v.postid = p.id and v.votetypeid = 2
    ) vu on true
    left join lateral (
        select count(*) as downvotes
        from votes v
        where v.postid = p.id and v.votetypeid = 3
    ) vd on true
    group by u.id
),
badge_summary as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased then 1 else 0 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_link_stats as (
    select
        pl.postid,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
        count(*) as total_links
    from postlinks pl
    group by pl.postid
),
question_metrics as (
    select
        rp.id as question_id,
        rp.title,
        rp.tags,
        rp.owneruserid,
        rp.owner_name,
        rp.reputation,
        rp.creationdate,
        rp.lastactivitydate,
        rp.score,
        rp.viewcount,
        rp.answercount,
        rp.commentcount,
        rp.favoritecount,
        pls.linked_count,
        pls.duplicate_count,
        pls.total_links,
        case when rp.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        (
            select cast(avg(a.score) as numeric(10,2))
            from posts a
            where a.parentid = rp.id and a.posttypeid = 2
        ) as avg_answer_score,
        (
            select max(a.score)
            from posts a
            where a.parentid = rp.id and a.posttypeid = 2
        ) as max_answer_score,
        (
            select count(*)
            from votes v
            where v.postid = rp.id and v.votetypeid = 2
        ) as upvote_events,
        (
            select count(*)
            from votes v
            where v.postid = rp.id and v.votetypeid = 3
        ) as downvote_events,
        (
            select count(*)
            from comments c
            where c.postid = rp.id
        ) as comment_events
    from recent_posts rp
    left join post_link_stats pls on pls.postid = rp.id
    where rp.posttypeid = 1
),
answerers as (
    select
        a.parentid as question_id,
        a.id as answer_id,
        a.owneruserid as answer_user_id,
        a.score as answer_score,
        a.creationdate as answer_created,
        row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn_score_desc,
        dense_rank() over (partition by a.parentid order by a.creationdate asc) as dr_first_answer
    from posts a
    where a.posttypeid = 2
),
first_best_answers as (
    select
        q.question_id,
        max(case when ans.rn_score_desc = 1 then ans.answer_id end) as top_answer_id,
        max(case when ans.dr_first_answer = 1 then ans.answer_id end) as first_answer_id,
        max(case when ans.rn_score_desc = 1 then ans.answer_user_id end) as top_answer_user_id,
        max(case when ans.dr_first_answer = 1 then ans.answer_user_id end) as first_answer_user_id
    from question_metrics q
    left join answerers ans on ans.question_id = q.question_id
    group by q.question_id
),
activity_windows as (
    select
        q.question_id,
        q.creationdate,
        q.lastactivitydate,
        extract(epoch from (q.lastactivitydate - q.creationdate)) as lifetime_seconds,
        percent_rank() over (order by q.viewcount nulls last) as view_pr,
        ntile(10) over (order by q.score nulls last) as score_decile,
        coalesce(q.viewcount,0) / nullif(greatest(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.creationdate)) / 3600.0, 1), 0) as views_per_hour
    from question_metrics q
),
closed_info as (
    select
        ph.postid,
        min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed,
        max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened,
        string_agg(distinct crt.name, ', ' order by crt.name) filter (where ph.posthistorytypeid = 10) as close_reasons
    from posthistory ph
    left join closereasontypes crt
        on ph.posthistorytypeid = 10
       and ph.comment ~ '^[0-9]+$'
       and cast(crt.id as text) = ph.comment
    group by ph.postid
),
tag_explode as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_metrics q
    where q.tags is not null
),
tag_meta as (
    select
        te.question_id,
        t.tagname,
        t.count as site_tag_count,
        t.ismoderatoronly,
        t.isrequired
    from tag_explode te
    left join tags t on lower(t.tagname) = lower(te.tagname)
),
tag_rollup as (
    select
        question_id,
        count(*) as tag_count,
        sum(case when ismoderatoronly then 1 else 0 end) as mod_only_tags,
        sum(case when isrequired then 1 else 0 end) as required_tags,
        max(site_tag_count) as max_site_tag_popularity,
        string_agg(tagname, '|' order by site_tag_count desc nulls last, tagname asc) as tag_list
    from tag_meta
    group by question_id
),
question_quality as (
    select
        q.question_id,
        q.title,
        q.owneruserid,
        q.owner_name,
        q.reputation,
        q.creationdate,
        q.lastactivitydate,
        q.score,
        q.viewcount,
        q.answercount,
        q.commentcount,
        q.favoritecount,
        q.linked_count,
        q.duplicate_count,
        q.total_links,
        aw.lifetime_seconds,
        aw.view_pr,
        aw.score_decile,
        aw.views_per_hour,
        fi.first_closed,
        fi.last_reopened,
        fi.close_reasons,
        tr.tag_count,
        tr.mod_only_tags,
        tr.required_tags,
        tr.max_site_tag_popularity,
        tr.tag_list,
        fba.top_answer_id,
        fba.first_answer_id,
        case
            when q.has_accepted = 1 then 'accepted'
            when coalesce(q.answercount,0) > 0 then 'answered'
            when fi.first_closed is not null then 'closed'
            else 'open'
        end as status_bucket,
        case
            when q.score >= 5 and q.viewcount >= 1000 and q.answercount >= 2 then 'high-impact'
            when q.score <= 0 and q.duplicate_count > 0 then 'low-quality-duplicate'
            when q.score <= 0 and coalesce(q.answercount,0) = 0 then 'unanswered-low'
            else 'normal'
        end as quality_bucket
    from question_metrics q
    left join activity_windows aw on aw.question_id = q.question_id
    left join closed_info fi on fi.postid = q.question_id
    left join tag_rollup tr on tr.question_id = q.question_id
    left join first_best_answers fba on fba.question_id = q.question_id
),
user_rollup as (
    select
        qq.owneruserid as user_id,
        count(*) as questions_asked,
        avg(coalesce(qq.score,0)) as avg_q_score,
        avg(coalesce(qq.viewcount,0)) as avg_q_views,
        sum(case when qq.status_bucket = 'accepted' then 1 else 0 end) as accepted_questions,
        sum(case when qq.quality_bucket = 'high-impact' then 1 else 0 end) as high_impact_questions,
        max(qq.creationdate) as last_question_date
    from question_quality qq
    group by qq.owneruserid
),
dupe_graph as (
    select
        q.question_id,
        count(distinct pl.relatedpostid) as distinct_dupe_targets,
        min(pl.creationdate) as first_dupe_link_time
    from question_metrics q
    left join postlinks pl
        on pl.postid = q.question_id
       and pl.linktypeid = 3
    group by q.question_id
),
final_scores as (
    select
        qq.*,
        coalesce(ur.questions_asked,0) as user_q_count,
        coalesce(ur.avg_q_score,0) as user_avg_q_score,
        coalesce(ur.avg_q_views,0) as user_avg_q_views,
        coalesce(ur.accepted_questions,0) as user_accepted_qs,
        coalesce(ur.high_impact_questions,0) as user_high_impact_qs,
        coalesce(ba.gold_badges,0) as user_gold_badges,
        coalesce(ba.silver_badges,0) as user_silver_badges,
        coalesce(ba.bronze_badges,0) as user_bronze_badges,
        coalesce(ba.tag_badges,0) as user_tag_badges,
        dg.distinct_dupe_targets,
        dg.first_dupe_link_time,
        (
            coalesce(qq.score,0)*2
            + greatest(coalesce(qq.viewcount,0)/100, 0)
            + coalesce(qq.answercount,0)*3
            + case when qq.status_bucket = 'accepted' then 10 when qq.status_bucket = 'answered' then 4 else 0 end
            - coalesce(qq.duplicate_count,0)*5
            + coalesce(qq.total_links,0)
            + least(coalesce(ur.avg_q_score,0), 10)
            + (coalesce(ba.gold_badges,0)*5 + coalesce(ba.silver_badges,0)*2 + coalesce(ba.bronze_badges,0))
        ) as composite_score
    from question_quality qq
    left join user_rollup ur on ur.user_id = qq.owneruserid
    left join badge_summary ba on ba.userid = qq.owneruserid
    left join dupe_graph dg on dg.question_id = qq.question_id
)
select
    fs.question_id,
    fs.title,
    fs.owneruserid,
    fs.owner_name,
    fs.reputation,
    fs.creationdate,
    fs.lastactivitydate,
    fs.status_bucket,
    fs.quality_bucket,
    fs.score,
    fs.viewcount,
    fs.answercount,
    fs.commentcount,
    fs.favoritecount,
    fs.linked_count,
    fs.duplicate_count,
    fs.total_links,
    fs.view_pr,
    fs.score_decile,
    round(cast(fs.views_per_hour as numeric), 4) as views_per_hour,
    fs.first_closed,
    fs.last_reopened,
    coalesce(fs.close_reasons, 'N/A') as close_reasons,
    fs.tag_count,
    fs.mod_only_tags,
    fs.required_tags,
    fs.max_site_tag_popularity,
    fs.tag_list,
    fs.top_answer_id,
    fs.first_answer_id,
    fs.user_q_count,
    round(cast(fs.user_avg_q_score as numeric), 2) as user_avg_q_score,
    round(cast(fs.user_avg_q_views as numeric), 2) as user_avg_q_views,
    fs.user_accepted_qs,
    fs.user_high_impact_qs,
    fs.user_gold_badges,
    fs.user_silver_badges,
    fs.user_bronze_badges,
    fs.user_tag_badges,
    fs.distinct_dupe_targets,
    fs.first_dupe_link_time,
    fs.composite_score,
    rank() over (order by fs.composite_score desc, fs.viewcount desc nulls last, fs.score desc nulls last) as rank_overall,
    row_number() over (partition by fs.status_bucket order by fs.composite_score desc) as rank_within_status
from final_scores fs
where
    (fs.reputation >= 1 or fs.owneruserid is null)
    and (fs.tag_count is null or fs.tag_count between 1 and 5)
    and not (fs.status_bucket = 'closed' and coalesce(fs.duplicate_count,0) = 0)
    and coalesce(fs.title, '') <> ''
order by fs.composite_score desc, fs.viewcount desc nulls last, fs.score desc nulls last
limit 250;