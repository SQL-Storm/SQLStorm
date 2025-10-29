with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
        row_number() over (order by u.reputation desc, u.id) as rn_global
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as q_count,
        count(case when p.posttypeid = 2 then 1 end) as a_count,
        sum(coalesce(p.score, 0)) as post_score_sum,
        avg(NULLIF(p.viewcount, 0)) as avg_views_nonzero,
        max(p.lastactivitydate) as last_post_activity,
        count(distinct p.parentid) filter (where p.posttypeid = 2 and p.parentid is not null) as distinct_questions_answered
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        avg(coalesce(c.score, 0)) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_quality as (
    select
        p.id as question_id,
        p.owneruserid as user_id,
        coalesce(p.score, 0) as q_score,
        coalesce(p.viewcount, 0) as q_views,
        p.answercount,
        p.acceptedanswerid,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        count(v.id) filter (where v.votetypeid = 2) as upvotes,
        count(v.id) filter (where v.votetypeid = 3) as downvotes,
        count(pl.id) filter (where pl.linktypeid = 3) as dup_links,
        count(pl2.id) filter (where pl2.linktypeid = 1) as linked_posts
    from posts p
    left join votes v on v.postid = p.id
    left join postlinks pl on pl.postid = p.id and pl.linktypeid = 3
    left join postlinks pl2 on pl2.postid = p.id and pl2.linktypeid = 1
    where p.posttypeid = 1
    group by p.id, p.owneruserid, p.score, p.viewcount, p.answercount, p.acceptedanswerid, p.closeddate
),
answer_quality as (
    select
        p.id as answer_id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        coalesce(p.score, 0) as a_score,
        count(v.id) filter (where v.votetypeid = 2) as upvotes,
        count(v.id) filter (where v.votetypeid = 3) as downvotes,
        bool_or(p.id = q.acceptedanswerid) as is_accepted
    from posts p
    join posts q on q.id = p.parentid and q.posttypeid = 1
    left join votes v on v.postid = p.id
    where p.posttypeid = 2
    group by p.id, p.parentid, p.owneruserid, p.score, q.acceptedanswerid
),
user_q_metrics as (
    select
        qq.user_id,
        count(*) as questions_posted,
        avg(qq.q_score) as avg_q_score,
        percentile_cont(0.5) within group (order by qq.q_score) as med_q_score,
        avg(qq.q_views) as avg_q_views,
        sum(case when qq.answercount > 0 then 1 else 0 end) as questions_with_answers,
        sum(case when qq.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
        sum(qq.is_closed) as questions_closed,
        sum(qq.upvotes) as q_upvotes,
        sum(qq.downvotes) as q_downvotes,
        sum(qq.dup_links) as q_dup_links,
        sum(qq.linked_posts) as q_linked_out
    from question_quality qq
    group by qq.user_id
),
user_a_metrics as (
    select
        aq.user_id,
        count(*) as answers_posted,
        avg(aq.a_score) as avg_a_score,
        percentile_cont(0.5) within group (order by aq.a_score) as med_a_score,
        sum(case when aq.is_accepted then 1 else 0 end) as answers_accepted,
        sum(aq.upvotes) as a_upvotes,
        sum(aq.downvotes) as a_downvotes
    from answer_quality aq
    group by aq.user_id
),
tag_usage as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name
    from posts p
    where p.posttypeid = 1 and p.tags is not null and p.owneruserid is not null
),
top_tags as (
    select
        tu.user_id,
        string_agg(tt.tag_name, ', ' order by tt.tag_count desc, tt.tag_name) as top3_tags
    from (
        select
            user_id,
            tag_name,
            count(*) as tag_count,
            row_number() over (partition by user_id order by count(*) desc, tag_name) as rn
        from tag_usage
        group by user_id, tag_name
    ) tt
    join tag_usage tu on tu.user_id = tt.user_id and tu.tag_name = tt.tag_name
    where tt.rn <= 3
    group by tu.user_id
),
user_flags as (
    select
        u.id as user_id,
        case
            when coalesce(ua.a_count, 0) = 0 and coalesce(ua.q_count, 0) = 0 then 'Lurker'
            when coalesce(ua.a_count, 0) > coalesce(ua.q_count, 0) * 2 then 'Answerer'
            when coalesce(ua.q_count, 0) > coalesce(ua.a_count, 0) * 2 then 'Questioner'
            else 'Balanced'
        end as activity_archetype,
        case
            when u.reputation >= 100000 then 'Elite'
            when u.reputation >= 10000 then 'High'
            when u.reputation >= 1000 then 'Medium'
            else 'Low'
        end as rep_tier
    from users u
    left join user_activity ua on ua.user_id = u.id
),
post_edits as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as total_edits,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as first_edit,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit
    from posthistory ph
    group by ph.postid
),
user_edit_density as (
    select
        p.owneruserid as user_id,
        avg(coalesce(pe.total_edits, 0)) as avg_post_edits,
        max(coalesce(pe.total_edits, 0)) as max_post_edits,
        count(*) filter (where coalesce(pe.total_edits, 0) = 0) as posts_never_edited
    from posts p
    left join post_edits pe on pe.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_times as (
    select
        u.id as user_id,
        min(least(coalesce(ua.last_post_activity, timestamp '1970-01-01'), coalesce(cs.last_comment_date, timestamp '1970-01-01'))) as first_activity,
        greatest(coalesce(ua.last_post_activity, timestamp '1970-01-01'), coalesce(cs.last_comment_date, timestamp '1970-01-01')) as last_activity
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join comment_stats cs on cs.user_id = u.id
    group by u.id, ua.last_post_activity, cs.last_comment_date
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.user_created,
        ru.location,
        ru.websiteurl,
        ru.net_votes,
        ua.q_count,
        ua.a_count,
        cs.comment_count,
        coalesce(uqm.questions_posted, 0) as questions_posted,
        coalesce(uam.answers_posted, 0) as answers_posted,
        coalesce(uam.answers_accepted, 0) as answers_accepted,
        coalesce(uqm.questions_with_accepted, 0) as questions_with_accepted,
        coalesce(br.total_badges, 0) as total_badges,
        uf.activity_archetype,
        uf.rep_tier,
        coalesce(ued.avg_post_edits, 0) as avg_post_edits,
        coalesce(ued.max_post_edits, 0) as max_post_edits,
        at.first_activity,
        at.last_activity,
        tt.top3_tags,
        (
            0.30 * ln(1 + greatest(ru.reputation, 0)) +
            0.15 * coalesce(uam.answers_posted, 0) +
            0.10 * coalesce(uam.answers_accepted, 0) * 2 +
            0.10 * coalesce(uqm.questions_posted, 0) +
            0.05 * coalesce(uqm.avg_q_score, 0) +
            0.05 * coalesce(uam.avg_a_score, 0) +
            0.05 * coalesce(br.gold_badges, 0) * 3 +
            0.03 * coalesce(br.silver_badges, 0) * 2 +
            0.02 * coalesce(br.bronze_badges, 0) +
            0.05 * coalesce(ua.distinct_questions_answered, 0) +
            0.05 * coalesce(ru.net_votes, 0) / NULLIF((select avg(upvotes - downvotes) from users), 0)
        ) as composite_score
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
    left join user_q_metrics uqm on uqm.user_id = ru.user_id
    left join user_a_metrics uam on uam.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join user_flags uf on uf.user_id = ru.user_id
    left join user_edit_density ued on ued.user_id = ru.user_id
    left join activity_times at on at.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
),
quartiles as (
    select
        r.*,
        ntile(4) over (order by composite_score desc nulls last) as composite_quartile,
        row_number() over (order by composite_score desc nulls last, reputation desc, user_id) as rank_overall,
        row_number() over (partition by rep_tier order by composite_score desc nulls last, reputation desc, user_id) as rank_within_tier
    from ranked_users r
),
dupe_close_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid = 10 and ph.comment in ('1','101')) as closed_duplicate_votes,
        count(*) filter (where ph.posthistorytypeid = 10 and ph.comment not in ('1','101')) as closed_other_votes
    from posts p
    left join posthistory ph on ph.postid = p.id and ph.posthistorytypeid = 10
    where p.owneruserid is not null and p.posttypeid = 1
    group by p.owneruserid
),
final_agg as (
    select
        q.user_id,
        q.displayname,
        q.reputation,
        q.rep_tier,
        q.activity_archetype,
        q.rank_overall,
        q.rank_within_tier,
        q.composite_quartile,
        q.composite_score,
        q.questions_posted,
        q.answers_posted,
        q.answers_accepted,
        q.questions_with_accepted,
        q.q_count,
        q.a_count,
        q.comment_count,
        q.total_badges,
        q.avg_post_edits,
        q.max_post_edits,
        q.first_activity,
        q.last_activity,
        q.top3_tags,
        coalesce(dcs.closed_duplicate_votes, 0) as closed_duplicate_votes,
        coalesce(dcs.closed_other_votes, 0) as closed_other_votes,
        case
            when q.last_activity is null then null
            when age(q.last_activity, q.user_created) < interval '7 days' then 'New'
            when age(q.last_activity, q.user_created) < interval '30 days' then 'Active-30'
            when age(q.last_activity, q.user_created) < interval '365 days' then 'Active-365'
            else 'Veteran'
        end as tenure_bucket
    from quartiles q
    left join dupe_close_stats dcs on dcs.user_id = q.user_id
)
select
    fa.user_id,
    coalesce(fa.displayname, '(unknown)') as displayname,
    fa.rep_tier,
    fa.activity_archetype,
    fa.tenure_bucket,
    fa.rank_overall,
    fa.rank_within_tier,
    fa.composite_quartile,
    round(cast(fa.composite_score as numeric), 3) as composite_score,
    fa.reputation,
    fa.questions_posted,
    fa.answers_posted,
    fa.answers_accepted,
    fa.questions_with_accepted,
    fa.q_count,
    fa.a_count,
    fa.comment_count,
    fa.total_badges,
    fa.avg_post_edits,
    fa.max_post_edits,
    coalesce(fa.top3_tags, 'none') as top3_tags,
    fa.closed_duplicate_votes,
    fa.closed_other_votes,
    fa.first_activity,
    fa.last_activity
from final_agg fa
where (
        fa.composite_quartile <= 2
        or (fa.rep_tier in ('Elite','High') and fa.activity_archetype <> 'Lurker')
        or (fa.answers_posted > 0 and fa.answers_accepted > 0)
      )
  and not (
        fa.rep_tier = 'Low'
        and fa.activity_archetype = 'Lurker'
        and coalesce(fa.comment_count, 0) = 0
      )
order by fa.composite_quartile, fa.rank_overall
limit 250;