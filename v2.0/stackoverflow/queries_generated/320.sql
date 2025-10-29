-- {"query": "320.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3099} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_newest
    from users u
),
active_questions as (
    select
        p.id as question_id,
        p.owneruserid as asker_id,
        p.creationdate,
        p.score,
        coalesce(p.viewcount, 0) as views,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.favoritecount,
        p.commentcount
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select min(creationdate) from users) -- force broader scan
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
answer_stats as (
    select
        a.question_id,
        count(*) as total_answers,
        sum(case when a.answer_score > 0 then 1 else 0 end) as positive_answers,
        max(a.answer_score) as best_answer_score,
        min(a.answer_score) as worst_answer_score,
        percentile_cont(0.5) within group (order by a.answer_score) as median_answer_score,
        avg(extract(epoch from (a.answer_date - q.creationdate)) / 3600.0) as avg_hours_to_answer
    from answers a
    join active_questions q on q.question_id = a.question_id
    group by a.question_id
),
accepted_answer_stats as (
    select
        q.question_id,
        aa.id as accepted_answer_id,
        aa.owneruserid as accepted_answerer_id,
        aa.score as accepted_answer_score,
        extract(epoch from (aa.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
    from active_questions q
    left join posts aa on aa.id = q.acceptedanswerid
),
question_votes as (
    select
        v.postid as question_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
question_comments as (
    select
        c.postid as question_id,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments
    from comments c
    group by c.postid
),
question_links as (
    select
        pl.postid as question_id,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as links_count,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_count
    from postlinks pl
    group by pl.postid
),
question_closures as (
    select
        ph.postid as question_id,
        min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_closed_at,
        bool_or(ph.posthistorytypeid = 11) as ever_reopened,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        string_agg(distinct
            case
                when ph.posthistorytypeid = 10 then
                    coalesce(
                        (select crt.name from closereasontypes crt where cast(ph.comment as int) = crt.id),
                        'Unknown'
                    )
            end
        , '|') as close_reasons
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag
    from active_questions q
    where q.tags is not null and q.tags like '<%>'
),
tag_stats as (
    select
        te.question_id,
        count(*) as tag_count,
        sum(case when lower(te.tag) similar to '(?:how-to|best-practices|beginner|advanced)' then 1 else 0 end) as meta_tag_count,
        max(case when t.ismoderatoronly then 1 else 0 end) as has_mod_only_tag,
        max(case when t.isrequired then 1 else 0 end) as has_required_tag
    from tag_expansion te
    left join tags t on t.tagname = te.tag
    group by te.question_id
),
user_badge_summary as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased then 1 else 0 end) as tag_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_owner as (
    select
        q.question_id,
        u.id as owner_id,
        u.displayname as owner_name,
        u.reputation as owner_rep,
        u.creationdate as owner_since,
        ub.total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges
    from active_questions q
    left join users u on u.id = q.asker_id
    left join user_badge_summary ub on ub.userid = u.id
),
question_quality as (
    select
        q.question_id,
        q.title,
        q.score,
        q.views,
        q.favoritecount,
        q.commentcount,
        qs.upvotes,
        qs.downvotes,
        qs.favorites as vote_favorites,
        qs.bounty_total,
        qc.comment_count as c_count,
        qc.max_comment_score,
        coalesce(qs.upvotes,0) - coalesce(qs.downvotes,0) as net_votes,
        coalesce(as1.total_answers,0) as total_answers,
        coalesce(as1.positive_answers,0) as positive_answers,
        coalesce(as1.best_answer_score, null) as best_answer_score,
        coalesce(as1.worst_answer_score, null) as worst_answer_score,
        as1.median_answer_score,
        as1.avg_hours_to_answer,
        case
            when q.closeddate is not null then 1 else 0
        end as is_closed,
        q.closeddate,
        q.acceptedanswerid,
        aa.accepted_answer_score,
        aa.hours_to_accept,
        tl.links_count,
        tl.dup_count,
        ts.tag_count,
        ts.meta_tag_count,
        ts.has_mod_only_tag,
        ts.has_required_tag,
        greatest(
            coalesce(q.score,0) * 3
            + (coalesce(qs.upvotes,0) - coalesce(qs.downvotes,0)) * 2
            + coalesce(q.views,0) / nullif(100,0)
            + coalesce(q.favoritecount,0) * 1.5
            + coalesce(as1.total_answers,0) * 0.5
            + coalesce(aa.accepted_answer_score,0) * 2
            - coalesce(tl.dup_count,0) * 5
            - case when q.closeddate is not null then 10 else 0 end
        , -100000) as quality_score
    from active_questions q
    left join question_votes qs on qs.question_id = q.question_id
    left join question_comments qc on qc.question_id = q.question_id
    left join answer_stats as1 on as1.question_id = q.question_id
    left join accepted_answer_stats aa on aa.question_id = q.question_id
    left join question_links tl on tl.question_id = q.question_id
    left join tag_stats ts on ts.question_id = q.question_id
),
ranked_questions as (
    select
        qq.*,
        row_number() over (order by quality_score desc, coalesce(views,0) desc, coalesce(score,0) desc, question_id desc) as rn_global,
        rank() over (order by coalesce(dup_count,0) desc, coalesce(score,0) desc) as rn_duplicates,
        dense_rank() over (partition by case when is_closed=1 then 1 else 0 end order by quality_score desc) as rn_by_closed,
        ntile(10) over (order by quality_score desc) as decile_quality
    from question_quality qq
),
owner_activity as (
    select
        qo.question_id,
        qo.owner_id,
        qo.owner_name,
        qo.owner_rep,
        qo.owner_since,
        rb.recent_questions,
        rb.recent_answers,
        rb.recent_comments,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges
    from question_owner qo
    left join user_badge_summary ub on ub.userid = qo.owner_id
    left join lateral (
        select
            sum(case when p.posttypeid = 1 and p.creationdate >= now() - interval '365 days' then 1 else 0 end) as recent_questions,
            sum(case when p.posttypeid = 2 and p.creationdate >= now() - interval '365 days' then 1 else 0 end) as recent_answers,
            coalesce((
                select count(*) from comments c where c.userid = qo.owner_id and c.creationdate >= now() - interval '365 days'
            ),0) as recent_comments
        from posts p
        where p.owneruserid = qo.owner_id
    ) rb on true
),
null_edge_cases as (
    select
        q.question_id,
        case when q.tags is null or trim(q.tags) = '' then 1 else 0 end as missing_tags,
        case when q.title is null or length(btrim(q.title)) = 0 then 1 else 0 end as missing_title,
        case when q.acceptedanswerid is null then 1 else 0 end as no_accepted_answer,
        case when q.closeddate is null then 0 else 1 end as was_closed
    from active_questions q
),
unpopular_but_high_views as (
    select
        question_id
    from question_quality
    where coalesce(net_votes,0) <= 0
      and coalesce(views,0) > percentile_cont(0.9) within group (order by coalesce(views,0))
),
final as (
    select
        rq.question_id,
        rq.title,
        rq.quality_score,
        rq.decile_quality,
        rq.net_votes,
        rq.views,
        rq.score as post_score,
        rq.total_answers,
        rq.acceptedanswerid,
        rq.accepted_answer_score,
        rq.hours_to_accept,
        rq.dup_count,
        rq.is_closed,
        rq.closeddate,
        rq.tag_count,
        rq.meta_tag_count,
        rq.has_mod_only_tag,
        rq.has_required_tag,
        oa.owner_id,
        oa.owner_name,
        oa.owner_rep,
        oa.total_badges,
        oa.gold_badges,
        oa.silver_badges,
        oa.bronze_badges,
        oa.recent_questions,
        oa.recent_answers,
        oa.recent_comments,
        ne.missing_tags,
        ne.missing_title,
        ne.no_accepted_answer,
        (select count(*) from answers a2 where a2.question_id = rq.question_id and a2.answer_score <= 0) as nonpositive_answers,
        (select count(*) from comments c2 where c2.postid = rq.question_id and c2.score < 0) as negative_comments,
        (select count(distinct pl2.relatedpostid) from postlinks pl2 where pl2.postid = rq.question_id and pl2.linktypeid = 1) as outgoing_links_unique,
        case when rq.question_id in (select question_id from unpopular_but_high_views) then 1 else 0 end as is_unpopular_but_high_views,
        case
            when coalesce(rq.views,0) = 0 then null
            else round( (rq.net_votes::numeric) / nullif(rq.views,0) * 1000, 3)
        end as votes_per_kview,
        case
            when rq.total_answers = 0 then null
            else round(coalesce(rq.positive_answers,0)::numeric / nullif(rq.total_answers,0), 3)
        end as positive_answer_ratio,
        rq.rn_global,
        rq.rn_duplicates,
        rq.rn_by_closed
    from ranked_questions rq
    left join owner_activity oa on oa.question_id = rq.question_id
    left join null_edge_cases ne on ne.question_id = rq.question_id
)
select *
from final
where (
        quality_score > (
            select avg(quality_score) + stddev_pop(quality_score)
            from ranked_questions
        )
        or (is_unpopular_but_high_views = 1 and no_accepted_answer = 1)
      )
  and coalesce(owner_rep,0) >= (
        select percentile_cont(0.25) within group (order by reputation)
        from users
      )
  and (
        case when missing_tags = 1 then 0 else 1 end = 1
      )
  and (
        (dup_count = 0 and is_closed = 0)
        or (dup_count > 0 and net_votes > 10)
      )
order by decile_quality asc, quality_score desc, views desc
limit 500;