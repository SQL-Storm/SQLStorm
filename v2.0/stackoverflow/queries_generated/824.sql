-- {"query": "824.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3217} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as tag_array
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= now() - interval '730 days'
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate
    from Posts a
    where a.PostTypeId = 2
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.LastAccessDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(nullif(trim(u.DisplayName), ''), '(anonymous)') as DisplayNameNorm,
        case
            when u.WebsiteUrl is null or u.WebsiteUrl !~* '^(https?://)' then null
            else u.WebsiteUrl
        end as WebsiteUrlNorm
    from Users u
),
q_stats as (
    select
        rq.QuestionId,
        rq.OwnerUserId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.tag_array,
        count(a.AnswerId) as ActualAnswerCount,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(a.AnswerScore) as AvgAnswerScore,
        count(distinct a.AnswerOwnerId) as DistinctAnswerers
    from recent_questions rq
    left join answers a on a.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.OwnerUserId, rq.Title, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount, rq.tag_array
),
q_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
        count(*) as TotalVotes
    from Votes v
    where v.PostId in (select QuestionId from recent_questions)
    group by v.PostId
),
q_links as (
    select
        pl.PostId as QuestionId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
    from PostLinks pl
    where pl.PostId in (select QuestionId from recent_questions)
    group by pl.PostId
),
q_closure as (
    select
        ph.PostId as QuestionId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedAt,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedAt,
        string_agg(distinct
            case
                when ph.PostHistoryTypeId = 10 then
                    case
                        when ph.Comment ~ '^\d+$' then
                            case cast(ph.Comment as int)
                                when 1 then 'Exact Duplicate'
                                when 2 then 'Off-topic'
                                when 3 then 'Subjective'
                                when 4 then 'Not a real question'
                                when 7 then 'Too localized'
                                when 10 then 'General reference'
                                when 20 then 'Noise'
                                when 101 then 'Duplicate'
                                when 102 then 'Off-topic'
                                when 103 then 'Needs details'
                                when 104 then 'Needs focus'
                                when 105 then 'Opinion-based'
                                else 'Other'
                            end
                        else 'Unknown'
                    end
                else null
            end, ','
        ) as CloseReasons
    from PostHistory ph
    where ph.PostId in (select QuestionId from recent_questions)
      and ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
tag_expansion as (
    select
        qs.QuestionId,
        unnest(qs.tag_array) as tagname
    from q_stats qs
),
tag_meta as (
    select
        te.QuestionId,
        te.tagname,
        t.Count as GlobalTagCount,
        t.IsModeratorOnly,
        t.IsRequired
    from tag_expansion te
    left join Tags t on lower(t.TagName) = lower(te.tagname)
),
tag_agg as (
    select
        QuestionId,
        count(*) as TagCount,
        sum(case when IsModeratorOnly then 1 else 0 end) as ModOnlyTags,
        sum(case when IsRequired then 1 else 0 end) as RequiredTags,
        avg(coalesce(GlobalTagCount,0)) as AvgTagGlobalCount,
        max(coalesce(GlobalTagCount,0)) as MaxTagGlobalCount,
        min(coalesce(GlobalTagCount,0)) as MinTagGlobalCount,
        string_agg(tagname, '|' order by tagname) as TagList
    from tag_meta
    group by QuestionId
),
badge_summary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
questioner_features as (
    select
        qs.QuestionId,
        ua.UserId as QuestionerId,
        ua.Reputation as QuestionerRep,
        ua.UserCreated as QuestionerCreated,
        ua.LastAccessDate as QuestionerLastAccess,
        ua.Location as QuestionerLocation,
        ua.UpVotes as QuestionerUpVotes,
        ua.DownVotes as QuestionerDownVotes,
        ua.ProfileViews as QuestionerProfileViews,
        bs.GoldBadges,
        bs.SilverBadges,
        bs.BronzeBadges,
        bs.TotalBadges,
        coalesce(bs.LastBadgeDate, ua.UserCreated) as LastBadgeDate
    from q_stats qs
    left join user_activity ua on ua.UserId = qs.OwnerUserId
    left join badge_summary bs on bs.UserId = qs.OwnerUserId
),
answerer_engagement as (
    select
        a.QuestionId,
        count(distinct a.AnswerOwnerId) as AnswererCount,
        avg(ua.Reputation) as AvgAnswererRep,
        max(ua.Reputation) as MaxAnswererRep,
        min(ua.Reputation) as MinAnswererRep
    from answers a
    left join user_activity ua on ua.UserId = a.AnswerOwnerId
    group by a.QuestionId
),
comment_metrics as (
    select
        c.PostId as QuestionId,
        count(*) as CommentCount,
        avg(coalesce(c.Score,0)) as AvgCommentScore,
        max(coalesce(c.Score,0)) as MaxCommentScore,
        sum(case when c.Text ~* '\b(thanks|thank you|great|awesome|nice)\b' then 1 else 0 end) as GratitudeComments,
        sum(case when c.Text ~* '\b(duplicate|dupe)\b' then 1 else 0 end) as DuplicateMentions
    from Comments c
    where c.PostId in (select QuestionId from recent_questions)
    group by c.PostId
),
time_windows as (
    select
        qs.QuestionId,
        qs.CreationDate,
        extract(epoch from (now() - qs.CreationDate))/3600.0 as HoursSinceAsked,
        case
            when qs.ViewCount is null or qs.ViewCount = 0 then null
            else qs.Score::numeric / nullif(qs.ViewCount,0)
        end as ScorePerView,
        case
            when qs.AnswerCount = 0 then null
            else qs.Score::numeric / qs.AnswerCount
        end as ScorePerAnswer
    from q_stats qs
),
rankings as (
    select
        qs.QuestionId,
        row_number() over (order by qs.Score desc nulls last) as RnByScore,
        dense_rank() over (order by coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0) desc) as DRByNetVotes,
        ntile(10) over (order by coalesce(qs.ViewCount,0) desc) as ViewDecile,
        percent_rank() over (order by coalesce(qs.ActualAnswerCount,0)) as PctByAnswers
    from q_stats qs
    left join q_votes qv on qv.QuestionId = qs.QuestionId
),
dup_chain as (
    select
        rq.QuestionId,
        exists (
            select 1
            from PostLinks pl
            where pl.PostId = rq.QuestionId
              and pl.LinkTypeId = 3
        ) as IsMarkedDuplicate,
        coalesce((
            select count(*)
            from PostLinks pl2
            where pl2.RelatedPostId = rq.QuestionId
              and pl2.LinkTypeId = 3
        ),0) as DuplicateOfCount
    from recent_questions rq
),
hotness as (
    select
        qs.QuestionId,
        (coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0))::numeric
          + coalesce(qs.ViewCount,0) / 100.0
          + coalesce(qs.ActualAnswerCount,0) * 2.0
          + case when qc.CloseEvents > 0 then -50 else 0 end
          + case when dc.IsMarkedDuplicate then -25 else 0 end
          - least(extract(epoch from (now() - qs.CreationDate))/3600.0, 240) / 10.0
          as HotnessScore
    from q_stats qs
    left join q_votes qv on qv.QuestionId = qs.QuestionId
    left join q_closure qc on qc.QuestionId = qs.QuestionId
    left join dup_chain dc on dc.QuestionId = qs.QuestionId
),
final as (
    select
        qs.QuestionId,
        qs.Title,
        qa.TagList,
        coalesce(qv.UpVotes,0) as UpVotes,
        coalesce(qv.DownVotes,0) as DownVotes,
        coalesce(qv.Favorites,0) as Favorites,
        coalesce(qv.BountyTotal,0) as BountyTotal,
        coalesce(ql.LinkedCount,0) as LinkedCount,
        coalesce(ql.DuplicateLinks,0) as DuplicateLinks,
        coalesce(qc.CloseEvents,0) as CloseEvents,
        qc.CloseReasons,
        coalesce(cm.CommentCount,0) as CommentCount,
        coalesce(cm.AvgCommentScore,0) as AvgCommentScore,
        coalesce(cm.GratitudeComments,0) as GratitudeComments,
        coalesce(cm.DuplicateMentions,0) as DuplicateMentions,
        coalesce(ae.AnswererCount,0) as AnswererCount,
        coalesce(ae.AvgAnswererRep,0) as AvgAnswererRep,
        tw.HoursSinceAsked,
        tw.ScorePerView,
        tw.ScorePerAnswer,
        coalesce(h.HotnessScore,0) as HotnessScore,
        rf.RnByScore,
        rf.DRByNetVotes,
        rf.ViewDecile,
        rf.PctByAnswers,
        qf.QuestionerId,
        qf.QuestionerRep,
        qf.GoldBadges,
        qf.SilverBadges,
        qf.BronzeBadges,
        case when qa.ModOnlyTags > 0 then true else false end as HasModOnlyTag,
        case when qa.RequiredTags > 0 then true else false end as HasRequiredTag,
        qa.AvgTagGlobalCount,
        qa.MaxTagGlobalCount,
        qa.MinTagGlobalCount
    from q_stats qs
    left join q_votes qv on qv.QuestionId = qs.QuestionId
    left join q_links ql on ql.QuestionId = qs.QuestionId
    left join q_closure qc on qc.QuestionId = qs.QuestionId
    left join tag_agg qa on qa.QuestionId = qs.QuestionId
    left join questioner_features qf on qf.QuestionId = qs.QuestionId
    left join answerer_engagement ae on ae.QuestionId = qs.QuestionId
    left join comment_metrics cm on cm.QuestionId = qs.QuestionId
    left join time_windows tw on tw.QuestionId = qs.QuestionId
    left join rankings rf on rf.QuestionId = qs.QuestionId
    left join hotness h on h.QuestionId = qs.QuestionId
)
select *
from final
where
    -- complicated predicate mix
    (UpVotes - DownVotes >= 0 or Favorites > 5)
    and (CloseEvents = 0 or (CloseEvents > 0 and coalesce(CloseReasons, '') not ilike '%duplicate%'))
    and (HasModOnlyTag is false or (HasModOnlyTag is true and ViewDecile >= 5))
    and (PctByAnswers is null or PctByAnswers >= 0.25)
    and (
        case when BountyTotal > 0 then HotnessScore + 10 else HotnessScore end
    ) > (
        select avg(h2.HotnessScore)
        from hotness h2
    )
union all
select *
from final
where
    -- contrasting set returning lower-hotness but high engagement
    HotnessScore <= (
        select avg(h3.HotnessScore) - stddev_pop(h3.HotnessScore)
        from hotness h3
    )
    and (CommentCount >= 10 or AnswererCount >= 3)
order by HotnessScore desc nulls last, UpVotes - DownVotes desc, Favorites desc
limit 200;