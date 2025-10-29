-- {"query": "971.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2893} 
with recent_years as (
    select generate_series(date_trunc('year', current_date) - interval '9 years', date_trunc('year', current_date), interval '1 year')::date as y
),
user_base as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate::date as user_created,
        coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)),''), 'Unknown') as country_guess,
        case when u.websiteurl ilike '%github.com%' then 1 else 0 end as has_github
    from users u
),
question_posts as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate::date as created,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.commentcount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        p.id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate::date as created,
        p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
q_enriched as (
    select
        q.*,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        case when q.closeddate is not null then 1 else 0 end as is_closed,
        cardinality(string_to_array(coalesce(nullif(substring(q.tags, 2, greatest(length(q.tags)-2,0)),''),''), '><')) as tag_count,
        (position('python' in coalesce(q.tags,'')) > 0)::int as has_python_tag
    from question_posts q
),
answers_agg as (
    select
        a.question_id,
        count(*) as answers_total,
        sum(case when a.answer_score > 0 then 1 else 0 end) as answers_positive,
        max(a.answer_score) as best_answer_score,
        min(a.created) as first_answer_date
    from answer_posts a
    group by a.question_id
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes
    from votes v
    where v.votetypeid in (2,3,8,9)
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comments_total,
        sum(case when c.score > 0 then 1 else 0 end) as comments_positive,
        max(c.score) as max_comment_score
    from comments c
    group by c.postid
),
hotness as (
    select
        q.id as post_id,
        q.created,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.has_accepted,
        q.is_closed,
        q.tag_count,
        q.has_python_tag,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.bounty_started,0) as bounty_started,
        coalesce(v.bounty_awarded,0) as bounty_awarded,
        coalesce(v.total_votes,0) as total_votes,
        coalesce(c.comments_total,0) as comments_total,
        coalesce(c.comments_positive,0) as comments_positive,
        coalesce(c.max_comment_score,0) as max_comment_score,
        coalesce(a.answers_total,0) as answers_total,
        coalesce(a.answers_positive,0) as answers_positive,
        coalesce(a.best_answer_score,0) as best_answer_score,
        a.first_answer_date,
        greatest(1, extract(epoch from (now() - q.creationdate))/3600.0) as age_hours,
        case when q.viewcount > 0 then ln(q.viewcount::numeric) else 0 end as ln_views
    from q_enriched q
    left join votes_agg v on v.postid = q.id
    left join comments_agg c on c.postid = q.id
    left join answers_agg a on a.question_id = q.id
),
hotness_scored as (
    select
        h.*,
        (
            0.50 * coalesce(h.score,0)
          + 0.30 * coalesce(h.upvotes - h.downvotes,0)
          + 0.10 * coalesce(h.favoritecount,0)
          + 0.20 * coalesce(h.answers_total,0)
          + 0.05 * coalesce(h.comments_total,0)
          + 0.15 * coalesce(h.best_answer_score,0)
          + 0.25 * coalesce(h.ln_views,0)
          + 0.40 * case when h.has_accepted = 1 then 5 else 0 end
          + 0.30 * case when h.has_python_tag = 1 then 3 else 0 end
          - 0.20 * case when h.is_closed = 1 then 10 else 0 end
        ) / (1.0 + ln(1.0 + h.age_hours)) as hot_score
    from hotness h
),
user_activity as (
    select
        qb.user_id,
        date_trunc('year', qb.created)::date as y,
        count(*) filter (where qb.score > 0) as q_pos,
        count(*) filter (where qb.score <= 0 or qb.score is null) as q_nonpos,
        sum(qb.viewcount) as q_views,
        sum(qb.answercount) as q_answers,
        sum(qb.favoritecount) as q_favs,
        sum(case when qb.closeddate is not null then 1 else 0 end) as q_closed
    from question_posts qb
    group by qb.user_id, date_trunc('year', qb.created)
),
user_badges as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as golds,
        count(*) filter (where b.class = 2) as silvers,
        count(*) filter (where b.class = 3) as bronzes,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
user_ranked as (
    select
        ub.user_id,
        ub.displayname,
        ub.reputation,
        ub.country_guess,
        ub.has_github,
        coalesce(ua.q_pos,0) as q_pos,
        coalesce(ua.q_nonpos,0) as q_nonpos,
        coalesce(ua.q_views,0) as q_views,
        coalesce(ua.q_answers,0) as q_answers,
        coalesce(ua.q_favs,0) as q_favs,
        coalesce(ua.q_closed,0) as q_closed,
        coalesce(ubad.golds,0) as golds,
        coalesce(ubad.silvers,0) as silvers,
        coalesce(ubad.bronzes,0) as bronzes,
        coalesce(ubad.tag_badges,0) as tag_badges,
        case
            when coalesce(ua.q_pos,0) + coalesce(ua.q_nonpos,0) = 0 then null
            else (coalesce(ua.q_pos,0)::numeric / nullif(coalesce(ua.q_pos,0) + coalesce(ua.q_nonpos,0),0))
        end as q_pos_rate
    from user_base ub
    left join (
        select ua1.user_id, ua1.y, ua1.q_pos, ua1.q_nonpos, ua1.q_views, ua1.q_answers, ua1.q_favs, ua1.q_closed
        from user_activity ua1
        where ua1.y = date_trunc('year', current_date)::date
    ) ua on ua.user_id = ub.user_id
    left join user_badges ubad on ubad.userid = ub.user_id
),
yearly_trends as (
    select
        y.y,
        count(distinct q.id) as questions,
        avg(q.score) as avg_score,
        percentile_cont(0.5) within group (order by q.score) as median_score,
        avg(coalesce(v.total_votes,0)) as avg_votes,
        sum(case when q.closeddate is not null then 1 else 0 end) as closed_count
    from recent_years y
    left join question_posts q
      on date_trunc('year', q.created)::date = y.y
    left join votes_agg v
      on v.postid = q.id
    group by y.y
),
dup_clusters as (
    select
        pl.relatedpostid as canonical_id,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        min(pl.creationdate) as first_dup_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
post_edits as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as content_edits,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit
    from posthistory ph
    group by ph.postid
),
final_posts as (
    select
        p.id,
        p.title,
        p.tags,
        p.owneruserid as user_id,
        hs.hot_score,
        dense_rank() over (order by hs.hot_score desc nulls last) as hot_rank,
        hs.score,
        hs.viewcount,
        hs.answers_total,
        hs.comments_total,
        hs.upvotes,
        hs.downvotes,
        coalesce(dc.dup_count,0) as dup_count,
        coalesce(pe.content_edits,0) as content_edits,
        pe.first_edit
    from hotness_scored hs
    join posts p on p.id = hs.post_id
    left join dup_clusters dc on dc.canonical_id = p.id
    left join post_edits pe on pe.postid = p.id
    where p.creationdate >= now() - interval '3 years'
),
ranked_users as (
    select
        ur.*,
        row_number() over (
            partition by coalesce(nullif(ur.country_guess,'Unknown'),'Unknown')
            order by coalesce(ur.q_pos_rate,0) desc nulls last, ur.reputation desc
        ) as country_rank
    from user_ranked ur
),
top_posts_per_user as (
    select
        fp.user_id,
        fp.id as post_id,
        fp.hot_score,
        row_number() over (partition by fp.user_id order by fp.hot_score desc nulls last) as rn
    from final_posts fp
)
select
    ru.user_id,
    coalesce(ru.displayname, concat('user#', ru.user_id::text)) as displayname,
    ru.country_guess,
    ru.reputation,
    ru.has_github,
    ru.q_pos,
    ru.q_nonpos,
    ru.q_views,
    ru.q_answers,
    ru.q_favs,
    ru.q_closed,
    ru.golds,
    ru.silvers,
    ru.bronzes,
    ru.tag_badges,
    round(coalesce(ru.q_pos_rate,0)::numeric, 4) as q_pos_rate,
    ru.country_rank,
    fp.post_id as top_post_id,
    round(fp.hot_score::numeric, 3) as top_post_hot_score,
    yt.y as trend_year,
    yt.questions as yearly_questions,
    round(coalesce(yt.avg_score,0)::numeric, 3) as yearly_avg_score,
    yt.median_score as yearly_median_score,
    yt.closed_count as yearly_closed
from ranked_users ru
left join top_posts_per_user tp on tp.user_id = ru.user_id and tp.rn = 1
left join final_posts fp on fp.id = tp.post_id
left join yearly_trends yt on yt.y = date_trunc('year', current_date)::date
where (ru.reputation >= 1000 or coalesce(ru.q_pos_rate,0) > 0.6 or ru.golds > 0)
  and (
        fp.hot_rank <= 100
        or (
            fp.hot_score is null
            and exists (
                select 1
                from question_posts qx
                where qx.user_id = ru.user_id
                  and qx.created >= now() - interval '1 year'
                  and qx.score > 0
            )
        )
      )
order by
    ru.country_guess asc nulls last,
    ru.country_rank asc,
    top_post_hot_score desc nulls last,
    ru.reputation desc
limit 500;