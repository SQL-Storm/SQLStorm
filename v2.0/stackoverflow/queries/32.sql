-- {"query": "32.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3343}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        date_trunc('month', u.creationdate) as cohort_month,
        coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as norm_location,
        row_number() over (order by u.creationdate desc, u.id) as rn_desc
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
question_posts as (
    select p.id, p.owneruserid, p.creationdate, p.score, p.viewcount, p.title, p.tags, p.answercount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id, p.parentid as question_id, p.owneruserid, p.creationdate, p.score
    from posts p
    where p.posttypeid = 2
),
post_activity as (
    select
        qp.id as question_id,
        qp.owneruserid as asker_id,
        qp.creationdate as question_created,
        qp.score as question_score,
        qp.viewcount,
        qp.title,
        qp.tags,
        qp.answercount,
        count(a.id) as answers_total,
        sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
        min(a.creationdate) as first_answer_time,
        max(a.creationdate) as last_answer_time
    from question_posts qp
    left join answer_posts a on a.question_id = qp.id
    group by qp.id, qp.owneruserid, qp.creationdate, qp.score, qp.viewcount, qp.title, qp.tags, qp.answercount
),
vote_aggs as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
tag_expanded as (
    select
        pa.question_id,
        unnest(string_to_array(substring(coalesce(pa.tags,''), 2, greatest(length(coalesce(pa.tags,'')) - 2, 0)), '><')) as tagname
    from post_activity pa
    where pa.tags is not null
),
hot_tag_cohorts as (
    select
        te.tagname,
        date_trunc('month', pa.question_created) as month_bucket,
        count(*) as questions_in_tag_month,
        avg(pa.question_score) as avg_q_score,
        percentile_disc(0.9) within group (order by pa.viewcount) as p90_views
    from tag_expanded te
    join post_activity pa on pa.question_id = te.question_id
    group by te.tagname, date_trunc('month', pa.question_created)
),
user_badges as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
comment_sentiment as (
    select
        c.postid,
        avg(c.score) as avg_comment_score,
        sum(case when lower(c.text) like '%thanks%' or lower(c.text) like '%thank you%' then 1 else 0 end) as thanks_count,
        sum(case when lower(c.text) similar to '%(great|awesome|nice|helpful|clear)%' then 1 else 0 end) as positive_words,
        sum(case when lower(c.text) similar to '%(bad|poor|wrong|confusing|unclear)%' then 1 else 0 end) as negative_words
    from comments c
    group by c.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_votes_events,
        sum(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopen_events
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
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
user_activity_rollup as (
    select
        u.id as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
        coalesce(sum(case when p.posttypeid = 1 then p.score else 0 end),0) as q_score_sum,
        coalesce(sum(case when p.posttypeid = 2 then p.score else 0 end),0) as a_score_sum,
        min(p.creationdate) as first_post_date,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_quality as (
    select
        pa.question_id,
        pa.asker_id,
        pa.question_created,
        pa.question_score,
        pa.viewcount,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(cs.avg_comment_score,0) as avg_comment_score,
        coalesce(cs.thanks_count,0) as thanks_count,
        coalesce(cs.positive_words,0) as positive_words,
        coalesce(cs.negative_words,0) as negative_words,
        coalesce(ce.first_close_date, null) as first_close_date,
        coalesce(ce.last_reopen_date, null) as last_reopen_date,
        pa.answers_total,
        pa.answers_positive,
        extract(epoch from (coalesce(pa.first_answer_time, pa.question_created) - pa.question_created))/60.0 as minutes_to_first_answer,
        case
            when pa.answercount is null then null
            when pa.answercount = 0 then 0.0
            else cast(pa.answers_positive as numeric) / nullif(pa.answercount,0)
        end as pos_answer_ratio
    from post_activity pa
    left join vote_aggs va on va.postid = pa.question_id
    left join comment_sentiment cs on cs.postid = pa.question_id
    left join close_events ce on ce.postid = pa.question_id
),
asker_features as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.norm_location,
        uar.q_count,
        uar.a_count,
        uar.q_score_sum,
        uar.a_score_sum,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.tag_badges,0) as tag_badges,
        case when uar.last_post_date is null then interval '0 seconds' else (uar.last_post_date - uar.first_post_date) end as user_active_span
    from recent_users ru
    left join user_activity_rollup uar on uar.user_id = ru.user_id
    left join user_badges ub on ub.userid = ru.user_id
),
tag_popularity as (
    select
        te.question_id,
        max(htc.questions_in_tag_month) as max_tag_q_in_month,
        avg(htc.avg_q_score) as mean_tag_q_score,
        max(htc.p90_views) as max_tag_p90_views
    from tag_expanded te
    join hot_tag_cohorts htc on htc.tagname = te.tagname
        and htc.month_bucket = date_trunc('month', (select pa.question_created from post_activity pa where pa.question_id = te.question_id))
    group by te.question_id
),
ranked_questions as (
    select
        qq.question_id,
        qq.asker_id,
        qq.question_created,
        qq.question_score,
        qq.viewcount,
        qq.upvotes,
        qq.downvotes,
        qq.favorites,
        qq.bounty_total,
        qq.avg_comment_score,
        qq.thanks_count,
        qq.positive_words,
        qq.negative_words,
        qq.first_close_date,
        qq.last_reopen_date,
        qq.answers_total,
        qq.answers_positive,
        qq.minutes_to_first_answer,
        qq.pos_answer_ratio,
        coalesce(tp.max_tag_q_in_month,0) as max_tag_q_in_month,
        coalesce(tp.mean_tag_q_score,0) as mean_tag_q_score,
        coalesce(tp.max_tag_p90_views,0) as max_tag_p90_views,
        sum(coalesce(qq.upvotes,0) - coalesce(qq.downvotes,0)) over (partition by qq.asker_id order by qq.question_created rows between unbounded preceding and current row) as asker_net_vote_cume,
        row_number() over (order by coalesce(qq.upvotes,0) - coalesce(qq.downvotes,0) desc, qq.viewcount desc, qq.question_created desc) as global_rank
    from question_quality qq
    left join tag_popularity tp on tp.question_id = qq.question_id
),
deduped_questions as (
    select
        rq.*,
        case
            when exists (
                select 1
                from dup_links dl
                where dl.dup_post_id = rq.question_id
            ) then 1 else 0
        end as is_marked_duplicate
    from ranked_questions rq
),
final_scored as (
    select
        dq.*,
        af.displayname as asker_name,
        af.reputation as asker_reputation,
        af.cohort_month,
        af.norm_location,
        af.q_count as asker_q_count,
        af.a_count as asker_a_count,
        af.gold_badges,
        af.silver_badges,
        af.bronze_badges,
        af.tag_badges,
        extract(epoch from af.user_active_span)/86400.0 as user_active_days,
        (
            coalesce(dq.upvotes,0)*3
            - coalesce(dq.downvotes,0)*2
            + least(coalesce(dq.viewcount,0)/100.0, 50)
            + coalesce(dq.favorites,0)*1.5
            + coalesce(dq.bounty_total,0)/50.0
            + coalesce(dq.avg_comment_score,0)
            + coalesce(dq.positive_words,0)*0.5
            - coalesce(dq.negative_words,0)*0.7
            + case when dq.is_marked_duplicate = 1 then -10 else 0 end
            + case when dq.first_close_date is not null and dq.last_reopen_date is null then -5 else 0 end
            + case when dq.pos_answer_ratio is null then 0 else dq.pos_answer_ratio*10 end
            + case when dq.minutes_to_first_answer is null then 0 else greatest(0, 30 - least(dq.minutes_to_first_answer, 180))/6.0 end
            + coalesce(dq.max_tag_q_in_month,0)/100.0
            + coalesce(dq.mean_tag_q_score,0)/2.0
            + coalesce(dq.max_tag_p90_views,0)/500.0
            + least(coalesce(af.reputation,0)/1000.0, 20)
        ) as composite_score
    from deduped_questions dq
    left join asker_features af on af.user_id = dq.asker_id
),
location_rollups as (
    select
        norm_location,
        count(*) as q_count,
        avg(composite_score) as avg_score,
        percentile_cont(0.5) within group (order by composite_score) as median_score,
        max(composite_score) as max_score
    from final_scored
    group by norm_location
),
cohort_trends as (
    select
        date_trunc('month', question_created) as month_bucket,
        count(*) as q_count,
        avg(composite_score) as avg_score,
        sum(case when is_marked_duplicate = 1 then 1 else 0 end) as dup_count
    from final_scored
    group by date_trunc('month', question_created)
)
select
    fs.question_id,
    fs.asker_id,
    coalesce(fs.asker_name, '(unknown)') as asker_name,
    fs.asker_reputation,
    fs.norm_location,
    fs.cohort_month,
    fs.question_created,
    fs.question_score,
    fs.viewcount,
    fs.upvotes,
    fs.downvotes,
    fs.favorites,
    fs.bounty_total,
    fs.answers_total,
    fs.answers_positive,
    round(coalesce(fs.pos_answer_ratio,0), 3) as pos_answer_ratio,
    round(coalesce(fs.minutes_to_first_answer,0), 2) as minutes_to_first_answer,
    fs.is_marked_duplicate,
    round(fs.composite_score, 3) as composite_score,
    fs.global_rank,
    lr.avg_score as location_avg_score,
    ct.avg_score as cohort_month_avg_score,
    case
        when fs.asker_reputation >= 100000 then 'Legend'
        when fs.asker_reputation >= 20000 then 'Veteran'
        when fs.asker_reputation >= 5000 then 'Experienced'
        when fs.asker_reputation >= 1000 then 'Intermediate'
        when fs.asker_reputation >= 100 then 'Novice'
        else 'New'
    end as asker_tier,
    case
        when fs.asker_name is null or trim(fs.asker_name) = '' then 1
        when lower(fs.asker_name) similar to '^\s*(user\d+|anonymous|deleted)\s*$' then 1
        else 0
    end as suspicious_name_flag
from final_scored fs
left join location_rollups lr on lr.norm_location = fs.norm_location
left join cohort_trends ct on ct.month_bucket = date_trunc('month', fs.question_created)
where
    fs.question_created >= (select date_trunc('month', max(question_created)) - interval '12 months' from final_scored)
    and (fs.upvotes - fs.downvotes) >= all (
        select (fs2.upvotes - fs2.downvotes)
        from final_scored fs2
        where fs2.asker_id = fs.asker_id
    )
order by fs.composite_score desc, fs.global_rank asc
limit 200;