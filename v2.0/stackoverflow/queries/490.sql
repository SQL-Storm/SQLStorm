-- {"query": "490.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2995}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        dense_rank() over (order by p.CreationDate desc, p.Id desc) as recency_rank
    from Posts p
    where p.PostTypeId = 1
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
question_activity as (
    select
        q.QuestionId,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        max(case when ph.PostHistoryTypeId in (4,5,6,7,8,9,24) then ph.CreationDate end) as LastEditDate,
        bool_or(case when ph.PostHistoryTypeId = 50 then true else false end) as WasCommunityBumped
    from recent_questions q
    left join Comments c on c.PostId = q.QuestionId
    left join Votes v on v.PostId = q.QuestionId
    left join PostHistory ph on ph.PostId = q.QuestionId
    group by q.QuestionId
),
tag_expansion as (
    select
        q.QuestionId,
        lower(trim(both ' ' from unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')))) as TagName
    from recent_questions q
    where q.Tags is not null
),
tag_stats as (
    select
        te.QuestionId,
        count(*) as TagCount,
        count(*) filter (where t.IsModeratorOnly = true) as ModOnlyTagCount,
        sum(coalesce(t.Count,0)) as TotalTagGlobalCount,
        string_agg(te.TagName, ',' order by te.TagName) as TagList
    from tag_expansion te
    left join Tags t on t.TagName = te.TagName
    group by te.QuestionId
),
answer_agg as (
    select
        a.QuestionId,
        count(*) as TotalAnswers,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers,
        avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore,
        min(a.AnswerCreationDate) as FirstAnswerDate,
        max(a.AnswerCreationDate) as LastAnswerDate
    from answers a
    group by a.QuestionId
),
accepted as (
    select
        q.QuestionId,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        p.AcceptedAnswerId
    from recent_questions q
    left join Posts p on p.Id = q.QuestionId
),
user_metrics as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreationDate,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormLocation
    from Users u
),
question_owner as (
    select
        q.QuestionId,
        u.UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.ProfileViews,
        u.NormLocation,
        extract(epoch from (timestamp '2024-10-01 12:34:56' - u.UserCreationDate)) / 86400.0 as UserAgeDays
    from recent_questions q
    left join user_metrics u on u.UserId = q.OwnerUserId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateOfCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DupCountSum
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedAt,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedAt,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesLogged
    from PostHistory ph
    group by ph.PostId
),
hotness as (
    select
        q.QuestionId,
        0.6 * ln(greatest(1, coalesce(qa.UpVotes,0) - coalesce(qa.DownVotes,0) + 1)) +
        0.3 * ln(greatest(1, coalesce(q.ViewCount,0) + coalesce(qa.CommentCount,0) + coalesce(a.TotalAnswers,0))) -
        0.1 * extract(epoch from (timestamp '2024-10-01 12:34:56' - q.CreationDate)) / 3600.0 as HotScore
    from recent_questions q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join answer_agg a on a.QuestionId = q.QuestionId
),
question_quality as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        qa.CommentCount,
        qa.UpVotes,
        qa.DownVotes,
        qa.Favorites,
        qa.LastEditDate,
        qa.WasCommunityBumped,
        coalesce(ts.TagCount, 0) as TagCount,
        coalesce(ts.ModOnlyTagCount, 0) as ModOnlyTagCount,
        coalesce(ts.TotalTagGlobalCount, 0) as TotalTagGlobalCount,
        ts.TagList,
        coalesce(a.TotalAnswers, 0) as TotalAnswers,
        coalesce(a.PositiveAnswers, 0) as PositiveAnswers,
        a.AvgAnswerScore,
        a.FirstAnswerDate,
        a.LastAnswerDate,
        acc.HasAccepted,
        acc.AcceptedAnswerId,
        qo.Reputation as OwnerReputation,
        qo.UpVotes as OwnerUpVotes,
        qo.DownVotes as OwnerDownVotes,
        qo.ProfileViews as OwnerProfileViews,
        qo.NormLocation as OwnerLocation,
        qo.UserAgeDays,
        dl.DuplicateOfCount,
        dl.LinkedCount,
        ce.FirstClosedAt,
        ce.LastReopenedAt,
        ce.CloseVotesLogged,
        h.HotScore,
        case
            when q.Score >= 5 and acc.HasAccepted = 1 and coalesce(a.TotalAnswers, 0) >= 2 then 'High'
            when q.Score between 1 and 4 then 'Medium'
            else 'Low'
        end as QualityBucket
    from recent_questions q
    left join question_activity qa on qa.QuestionId = q.QuestionId
    left join tag_stats ts on ts.QuestionId = q.QuestionId
    left join answer_agg a on a.QuestionId = q.QuestionId
    left join accepted acc on acc.QuestionId = q.QuestionId
    left join question_owner qo on qo.QuestionId = q.QuestionId
    left join duplicate_links dl on dl.QuestionId = q.QuestionId
    left join close_events ce on ce.QuestionId = q.QuestionId
    left join hotness h on h.QuestionId = q.QuestionId
),
ranked as (
    select
        qq.QuestionId,
        qq.Title,
        qq.CreationDate,
        qq.Score,
        qq.ViewCount,
        qq.CommentCount,
        qq.UpVotes,
        qq.DownVotes,
        qq.Favorites,
        qq.LastEditDate,
        qq.WasCommunityBumped,
        qq.TagCount,
        qq.ModOnlyTagCount,
        qq.TotalTagGlobalCount,
        qq.TagList,
        qq.TotalAnswers,
        qq.PositiveAnswers,
        qq.AvgAnswerScore,
        qq.FirstAnswerDate,
        qq.LastAnswerDate,
        qq.HasAccepted,
        qq.AcceptedAnswerId,
        qq.OwnerReputation,
        qq.OwnerUpVotes,
        qq.OwnerDownVotes,
        qq.OwnerProfileViews,
        qq.OwnerLocation,
        qq.UserAgeDays,
        qq.DuplicateOfCount,
        qq.LinkedCount,
        qq.FirstClosedAt,
        qq.LastReopenedAt,
        qq.CloseVotesLogged,
        qq.HotScore,
        qq.QualityBucket,
        row_number() over (order by qq.HotScore desc NULLS LAST, qq.Score desc NULLS LAST, qq.ViewCount desc NULLS LAST) as HotRank,
        row_number() over (order by qq.Score desc NULLS LAST, qq.ViewCount desc NULLS LAST) as ScoreRank,
        ntile(10) over (order by coalesce(qq.ViewCount,0) desc) as ViewDecile,
        avg(qq.Score) over () as GlobalAvgScore,
        qq.ViewCount as ViewCountForMedian
    from question_quality qq
),
median_views as (
    select percentile_cont(0.5) within group (order by ViewCountForMedian) as GlobalMedianViews
    from ranked
),
ranked_with_median as (
    select r.*, m.GlobalMedianViews
    from ranked r
    cross join median_views m
),
owner_badges as (
    select
        b.UserId,
        count(*) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldCount,
        count(*) filter (where b.Class = 2) as SilverCount,
        count(*) filter (where b.Class = 3) as BronzeCount,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
final_set as (
    select
        r.QuestionId,
        r.Title,
        r.QualityBucket,
        r.HotScore,
        r.HotRank,
        r.ScoreRank,
        r.ViewDecile,
        r.Score,
        r.ViewCount,
        r.CommentCount,
        r.UpVotes,
        r.DownVotes,
        r.Favorites,
        r.TagCount,
        r.TotalTagGlobalCount,
        r.TotalAnswers,
        r.PositiveAnswers,
        r.HasAccepted,
        r.OwnerReputation,
        r.OwnerLocation,
        coalesce(ob.BadgeCount, 0) as OwnerBadgeCount,
        coalesce(ob.GoldCount, 0) as OwnerGoldBadges,
        r.DuplicateOfCount,
        r.LinkedCount,
        r.FirstClosedAt,
        r.LastReopenedAt,
        r.CreationDate,
        r.LastEditDate,
        r.GlobalAvgScore,
        r.GlobalMedianViews,
        case
            when r.TagCount = 0 then 'untagged'
            when r.TagList ilike '%sql%' then 'sql-related'
            when r.TagList ilike '%python%' then 'python-related'
            else 'other'
        end as TopicBucket,
        case
            when r.OwnerReputation is null then 'anonymous'
            when r.OwnerReputation >= 100000 then 'legend'
            when r.OwnerReputation >= 10000 then 'expert'
            when r.OwnerReputation >= 1000 then 'experienced'
            else 'newbie'
        end as AuthorTier
    from ranked_with_median r
    left join question_owner qo on qo.QuestionId = r.QuestionId
    left join owner_badges ob on ob.UserId = qo.UserId
),
topn as (
    select *
    from (
        select
            fs.*,
            row_number() over (partition by QualityBucket order by HotRank, ScoreRank, ViewCount desc NULLS LAST) as rn
        from final_set fs
    ) t
    where t.rn <= 50
),
null_logic as (
    select
        t.*,
        coalesce(nullif(OwnerLocation, 'Unknown'), 'N/A') as OwnerLocationDisplay,
        coalesce(cast(FirstClosedAt as varchar), 'never') as FirstClosedAtStr,
        coalesce(cast(LastReopenedAt as varchar), 'never') as LastReopenedAtStr
    from topn t
),
stringy as (
    select
        n.*,
        left(regexp_replace(coalesce(n.Title,''), '\s+', ' ', 'g'), 120) as TitleShort,
        initcap(split_part(coalesce(n.OwnerLocationDisplay,'N/A'), ',', 1)) as OwnerCountryGuess,
        concat_ws(' | ',
            'QID='||n.QuestionId,
            'Q='||coalesce(left(regexp_replace(coalesce(n.Title,''), '\s+', ' ', 'g'), 120),''),
            'QBKT='||n.QualityBucket,
            'HS='||coalesce(cast(round(coalesce(n.HotScore,0)::numeric,2) as text),'null'),
            'ANS='||cast(coalesce(n.TotalAnswers,0) as text),
            'ACC='||cast(coalesce(n.HasAccepted,0) as text),
            'REP='||coalesce(cast(n.OwnerReputation as text),'null'),
            'BADGES='||cast(coalesce(n.OwnerBadgeCount,0) as text)
        ) as SummaryLine
    from null_logic n
),
dups AS (
    select QuestionId from duplicate_links where DuplicateOfCount > 0
),
mixed as (
    select * from stringy s
    where not exists (
        select 1
        from close_events ce
        where ce.QuestionId = s.QuestionId
          and coalesce(ce.CloseVotesLogged,0) >= 5
    )
    union all
    select s.*
    from stringy s
    where s.TopicBucket in ('sql-related','python-related')
      and s.HotRank <= 100
),
with_flags as (
    select
        m.*,
        case when exists (select 1 from dups d where d.QuestionId = m.QuestionId) then 1 else 0 end as IsDuplicate,
        case when coalesce(m.OwnerBadgeCount,0) >= 50 or coalesce(m.OwnerGoldBadges,0) >= 5 then 1 else 0 end as IsNotableAuthor,
        case when m.TopicBucket in ('sql-related','python-related') then 1 else 0 end as IsFeaturedTopic
    from mixed m
)
select
    wf.QuestionId,
    wf.TitleShort as Title,
    wf.QualityBucket,
    wf.AuthorTier,
    wf.OwnerLocationDisplay as OwnerLocation,
    wf.OwnerBadgeCount,
    wf.OwnerGoldBadges,
    wf.Score,
    wf.ViewCount,
    wf.TotalAnswers,
    wf.PositiveAnswers,
    wf.HasAccepted,
    wf.TagCount,
    wf.TotalTagGlobalCount,
    wf.DuplicateOfCount,
    wf.LinkedCount,
    wf.HotScore,
    wf.HotRank,
    wf.ScoreRank,
    wf.ViewDecile,
    wf.FirstClosedAtStr,
    wf.LastReopenedAtStr,
    wf.SummaryLine,
    wf.IsDuplicate,
    wf.IsNotableAuthor,
    wf.IsFeaturedTopic
from with_flags wf
where (wf.QualityBucket <> 'Low' or wf.IsFeaturedTopic = 1)
  and (wf.IsDuplicate = 0 or wf.ViewCount > coalesce(wf.GlobalMedianViews, 0))
order by
    wf.IsFeaturedTopic desc,
    wf.QualityBucket desc,
    wf.HotRank asc,
    wf.ScoreRank asc,
    wf.ViewCount desc
limit 250;