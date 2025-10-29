-- {"query": "475.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3508} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate as user_creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
        row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
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
        split_part(regexp_replace(t.tagname, '\s+', ' ', 'g'), ' ', 1) as tag_primary -- cheap op to touch string funcs
    from posts p
    left join lateral (
        select tagname
        from tags tg
        where tg.tagname = any (string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))
        order by tg.count desc nulls last
        limit 1
    ) t on true
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner,
        a.score as answer_score,
        a.creationdate as answer_creationdate
    from posts a
    where a.posttypeid = 2
),
user_activity as (
    select
        ru.user_id,
        count(distinct tq.question_id) as q_count,
        count(distinct an.answer_id) as a_count,
        count(distinct c.id) as c_count,
        sum(coalesce(vu.upvotes, 0)) as upvotes_cast,
        sum(coalesce(vd.downvotes, 0)) as downvotes_cast,
        sum(coalesce(f.favs, 0)) as favorites_cast
    from recent_users ru
    left join tagged_questions tq on tq.owneruserid = ru.user_id
    left join answers an on an.answer_owner = ru.user_id
    left join comments c on c.userid = ru.user_id
    left join lateral (
        select count(*) as upvotes from votes v where v.userid = ru.user_id and v.votetypeid = 2
    ) vu on true
    left join lateral (
        select count(*) as downvotes from votes v where v.userid = ru.user_id and v.votetypeid = 3
    ) vd on true
    left join lateral (
        select count(*) as favs from votes v where v.userid = ru.user_id and v.votetypeid = 5
    ) f on true
    group by ru.user_id
),
post_metrics as (
    select
        tq.question_id,
        tq.owneruserid,
        tq.creationdate as q_creationdate,
        tq.score as q_score,
        tq.viewcount as q_views,
        tq.title,
        tq.tags,
        tq.tag_primary,
        count(distinct an.answer_id) as answers_cnt,
        max(case when an.answer_id = p.acceptedanswerid then 1 else 0 end) as has_accepted,
        sum(coalesce(v2ups.uv,0)) as ups_on_q,
        sum(coalesce(v2dns.dv,0)) as dns_on_q,
        count(distinct cm.id) filter (where cm.score > 0) as positive_comments
    from tagged_questions tq
    left join posts p on p.id = tq.question_id
    left join answers an on an.question_id = tq.question_id
    left join lateral (
        select count(*) as uv from votes v where v.postid = tq.question_id and v.votetypeid = 2
    ) v2ups on true
    left join lateral (
        select count(*) as dv from votes v where v.postid = tq.question_id and v.votetypeid = 3
    ) v2dns on true
    left join comments cm on cm.postid = tq.question_id
    group by tq.question_id, tq.owneruserid, tq.creationdate, tq.score, tq.viewcount, tq.title, tq.tags, tq.tag_primary
),
dup_map as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as canonical_post_id,
        pl.creationdate as link_created,
        lt.name as link_type_name
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where pl.linktypeid = 3
),
question_lifecycle as (
    select
        ph.postid as question_id,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (10,35)) as first_close_or_migrate,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (11,36)) as first_reopen_or_migrated_here,
        bool_or(ph.posthistorytypeid = 19) as was_protected,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 50) as last_community_bump,
        -- extract duplicate reason ids embedded in comment field when type = 10
        array_agg(distinct cast(nullif(trim(ph.comment), '') as int)) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^\d+$') as close_reasons_ids
    from posthistory ph
    group by ph.postid
),
tag_popularity as (
    select
        tg.tagname,
        tg.count as tag_global_count,
        ntile(10) over (order by tg.count desc nulls last, tg.tagname) as tag_popularity_decile
    from tags tg
),
ranked_questions as (
    select
        pm.*,
        ql.first_close_or_migrate,
        ql.first_reopen_or_migrated_here,
        ql.was_protected,
        ql.last_community_bump,
        ql.close_reasons_ids,
        dm.canonical_post_id,
        dm.link_type_name,
        tp.tag_global_count,
        tp.tag_popularity_decile,
        row_number() over (
            partition by coalesce(dm.canonical_post_id, pm.question_id)
            order by pm.q_score desc nulls last, pm.q_views desc nulls last, pm.q_creationdate
        ) as rn_within_thread
    from post_metrics pm
    left join question_lifecycle ql on ql.question_id = pm.question_id
    left join dup_map dm on dm.dup_post_id = pm.question_id
    left join tag_popularity tp on tp.tagname = pm.tag_primary
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.user_creationdate,
        ru.lastaccessdate,
        ru.websiteurl_norm,
        ua.q_count,
        ua.a_count,
        ua.c_count,
        ua.upvotes_cast,
        ua.downvotes_cast,
        ua.favorites_cast,
        sum(pm.q_views) as total_views_on_own_questions,
        sum(pm.q_score) as total_score_on_own_questions,
        avg(pm.q_score) as avg_score_on_own_questions,
        max(pm.answers_cnt) as max_answers_on_a_question,
        count(*) filter (where pm.has_accepted = 1) as questions_with_accepted,
        count(*) filter (where rq.link_type_name = 'Duplicate') as dup_marked_questions
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join post_metrics pm on pm.owneruserid = ru.user_id
    left join ranked_questions rq on rq.question_id = pm.question_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.location, ru.user_creationdate, ru.lastaccessdate, ru.websiteurl_norm,
             ua.q_count, ua.a_count, ua.c_count, ua.upvotes_cast, ua.downvotes_cast, ua.favorites_cast
),
top_tags_per_user as (
    select
        pm.owneruserid as user_id,
        unnest(string_to_array(substring(pm.tags, 2, length(pm.tags)-2), '><')) as tagname,
        count(*) as q_per_tag,
        sum(pm.q_score) as score_per_tag
    from post_metrics pm
    where pm.tags is not null
    group by pm.owneruserid, unnest(string_to_array(substring(pm.tags, 2, length(pm.tags)-2), '><'))
),
top_tag_choice as (
    select distinct on (tt.user_id)
        tt.user_id,
        tt.tagname as top_tag,
        tt.q_per_tag,
        tt.score_per_tag
    from top_tags_per_user tt
    order by tt.user_id, tt.q_per_tag desc, tt.score_per_tag desc, tt.tagname
),
accepted_answerers as (
    select
        p.owneruserid as asker_id,
        a.owneruserid as answerer_id,
        count(*) as accepted_count
    from posts q
    join posts a on a.parentid = q.id and a.posttypeid = 2
    join posts p on p.id = q.id and p.posttypeid = 1
    where q.acceptedanswerid = a.id
    group by p.owneruserid, a.owneruserid
),
user_peer_network as (
    select
        ar.asker_id as user_id,
        count(distinct case when ar.accepted_count >= 1 then ar.answerer_id end) as distinct_accept_partners,
        sum(ar.accepted_count) as total_accepts_from_peers
    from accepted_answerers ar
    group by ar.asker_id
),
saves_versus_favorites as (
    select
        pm.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 5) as favs_on_own,
        count(*) filter (where v.votetypeid = 2) as ups_on_own
    from post_metrics pm
    left join votes v on v.postid = pm.question_id and v.userid is not null
    group by pm.owneruserid
),
null_edge_cases as (
    select
        u.id as user_id,
        case
            when u.displayname is null then '(anon)'
            when trim(u.displayname) = '' then '(blank)'
            else u.displayname
        end as displayname_clean,
        nullif(u.location, '') as location_nullif,
        coalesce(nullif(u.profileimageurl, ''), 'no-image') as profileimageurl_norm
    from users u
)
select
    ur.user_id,
    coalesce(nec.displayname_clean, ur.displayname) as displayname,
    ur.reputation,
    coalesce(ur.location, nec.location_nullif, 'Unknown') as location,
    ur.user_creationdate,
    ur.lastaccessdate,
    ur.websiteurl_norm,
    coalesce(ur.q_count, 0) as q_count,
    coalesce(ur.a_count, 0) as a_count,
    coalesce(ur.c_count, 0) as c_count,
    coalesce(ur.upvotes_cast, 0) as upvotes_cast,
    coalesce(ur.downvotes_cast, 0) as downvotes_cast,
    coalesce(ur.favorites_cast, 0) as favorites_cast,
    coalesce(ur.total_views_on_own_questions, 0) as total_views_on_own_questions,
    coalesce(ur.total_score_on_own_questions, 0) as total_score_on_own_questions,
    round(coalesce(ur.avg_score_on_own_questions, 0), 2) as avg_score_on_own_questions,
    coalesce(ur.max_answers_on_a_question, 0) as max_answers_on_a_question,
    coalesce(ur.questions_with_accepted, 0) as questions_with_accepted,
    coalesce(ur.dup_marked_questions, 0) as dup_marked_questions,
    coalesce(ttc.top_tag, 'none') as top_tag,
    t.tag_global_count as top_tag_global_count,
    t.tag_popularity_decile as top_tag_decile,
    coalesce(upn.distinct_accept_partners, 0) as distinct_accept_partners,
    coalesce(upn.total_accepts_from_peers, 0) as total_accepts_from_peers,
    coalesce(svf.favs_on_own, 0) as favorites_on_own_content,
    coalesce(svf.ups_on_own, 0) as upvotes_on_own_content,
    case
        when coalesce(ur.q_count, 0) + coalesce(ur.a_count, 0) + coalesce(ur.c_count, 0) = 0 then 'inactive'
        when coalesce(ur.q_count, 0) > coalesce(ur.a_count, 0) then 'asker-leaning'
        when coalesce(ur.a_count, 0) > coalesce(ur.q_count, 0) then 'answerer-leaning'
        else 'balanced'
    end as activity_profile,
    case
        when coalesce(ur.total_score_on_own_questions, 0) >= 100 then 'high-impact'
        when coalesce(ur.total_score_on_own_questions, 0) between 20 and 99 then 'medium-impact'
        when coalesce(ur.total_score_on_own_questions, 0) between 1 and 19 then 'low-impact'
        else 'no-impact'
    end as impact_band,
    -- correlated scalar subquery to fetch last duplicate mark time on user's questions
    (
        select max(pl.creationdate)
        from postlinks pl
        join posts qp on qp.id = pl.postid and qp.posttypeid = 1
        where pl.linktypeid = 3 and qp.owneruserid = ur.user_id
    ) as last_duplicate_marked_at,
    -- existence checks with complex predicate and null logic
    exists (
        select 1
        from posts px
        left join comments cx on cx.postid = px.id
        where px.owneruserid = ur.user_id
          and px.posttypeid = 1
          and (px.tags is not null and position('><' in px.tags) > 0)
          and (
                (cx.id is null and px.viewcount > 1000)
             or (cx.id is not null and coalesce(cx.score, 0) >= 5)
          )
    ) as has_popular_or_discussed_q,
    -- windowed percentiles over users by reputation bucket
    percentile_disc(0.9) within group (order by coalesce(ur.total_score_on_own_questions, 0)) over (partition by case when ur.reputation >= 10000 then '10k+' when ur.reputation >= 2000 then '2k-10k' else '<2k' end) as p90_total_qscore_by_rep_bucket
from user_rollup ur
left join top_tag_choice ttc on ttc.user_id = ur.user_id
left join tag_popularity t on t.tagname = ttc.top_tag
left join user_peer_network upn on upn.user_id = ur.user_id
left join saves_versus_favorites svf on svf.user_id = ur.user_id
left join null_edge_cases nec on nec.user_id = ur.user_id
where
    -- complicated predicate mixing null logic and expressions
    (
        (coalesce(ur.q_count, 0) + coalesce(ur.a_count, 0) + coalesce(ur.c_count, 0)) >= 5
        or (coalesce(ur.total_views_on_own_questions, 0) > 5000 and coalesce(ur.avg_score_on_own_questions, 0) >= 1)
        or (exists (
                select 1
                from ranked_questions rq
                where rq.owneruserid = ur.user_id
                  and rq.rn_within_thread = 1
                  and coalesce(rq.q_score, 0) >= 10
            ))
    )
  and (ttc.top_tag is null or t.tag_popularity_decile <= 7 or ur.reputation >= 1000)
order by
    impact_band desc,
    activity_profile,
    coalesce(ur.total_score_on_own_questions, 0) desc,
    coalesce(ur.total_views_on_own_questions, 0) desc,
    ur.reputation desc,
    ur.user_id
limit 500;