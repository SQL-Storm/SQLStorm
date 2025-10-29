-- {"query": "2317.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412} 
with RecursiveQuestionRanks as (
    select
        p.Id,
        p.Title,
        p.Score,
        u.DisplayName as OwnerName,
        u.Reputation,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.CreationDate asc) as QuestionRank
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId = 1
        and p.Title is not null
        and p.Score > 0
), TopQuestions as (
    select * from RecursiveQuestionRanks where QuestionRank <= 100
), AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByUsers
    from
        Posts a
    where
        a.PostTypeId = 2
        and a.Score is not null
    group by
        a.ParentId
), PostLinksFiltered as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from
        PostLinks pl
        join LinkTypes lt on pl.LinkTypeId = lt.Id
    where
        lt.Name in ('Linked', 'Duplicate')
), BadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgesEarned
    from
        Badges b
    group by
        b.UserId,
        b.Class
), UserAggregates as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(bcGold.BadgesEarned, 0) as GoldBadges,
        coalesce(bcSilver.BadgesEarned, 0) as SilverBadges,
        coalesce(bcBronze.BadgesEarned, 0) as BronzeBadges,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        case when u.Reputation > 0 then round(cast(u.UpVotes as numeric) / nullif(u.DownVotes,0), 2) else null end as UpDownRatio,
        u.Location,
        u.WebsiteUrl
    from
        Users u
        left join BadgeCounts bcGold on u.Id = bcGold.UserId and bcGold.Class = 1
        left join BadgeCounts bcSilver on u.Id = bcSilver.UserId and bcSilver.Class = 2
        left join BadgeCounts bcBronze on u.Id = bcBronze.UserId and bcBronze.Class = 3
), LatestComments as (
    select distinct on (c.PostId)
        c.PostId,
        c.Text as LatestCommentText,
        c.CreationDate as LatestCommentDate,
        c.UserDisplayName as LatestCommentUser
    from
        Comments c
    order by
        c.PostId,
        c.CreationDate desc
), QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as ClosedAt
    from
        PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where
        ph.PostHistoryTypeId = 10
), QuestionWindow as (
    select
        tq.*,
        coalesce(ast.AnswerCount, 0) as AnswerCount,
        coalesce(ast.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ast.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ast.AnsweredByUsers, 0) as AnsweredByUsers,
        la.LatestCommentText,
        la.LatestCommentDate,
        la.LatestCommentUser,
        qcr.CloseReason,
        qcr.ClosedAt,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.Reputation as QuestionOwnerReputation,
        ua.UpDownRatio as OwnerUpDownRatio,
        ua.Location as OwnerLocation
    from
        TopQuestions tq
        left join AnswerStats ast on tq.Id = ast.QuestionId
        left join LatestComments la on tq.Id = la.PostId
        left join QuestionCloseReasons qcr on tq.Id = qcr.PostId
        left join Users u on tq.OwnerUserId = u.Id
        left join UserAggregates ua on u.Id = ua.Id
), RankedQuestions as (
    select
        *,
        rank() over (order by Score desc, AnswerCount desc, AvgAnswerScore desc) as GlobalRank
    from
        QuestionWindow
)
select
    rq.GlobalRank,
    rq.Id as QuestionId,
    rq.Title,
    rq.Score as QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AnsweredByUsers,
    case 
        when rq.CloseReason is not null then rq.CloseReason
        else 'Open'
    end as Status,
    rq.ClosedAt,
    rq.LatestCommentDate,
    substring(rq.LatestCommentText, 1, 100) as LatestCommentPreview,
    rq.LatestCommentUser,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.QuestionOwnerReputation,
    rq.OwnerUpDownRatio,
    rq.OwnerLocation,
    coalesce(array_agg(distinct concat(lt.Name, ': ', pl.RelatedPostId)) filter (where pl.PostId = rq.Id), array[]::text[]) as LinkedPostsInfo
from
    RankedQuestions rq
    left join PostLinksFiltered pl on pl.PostId = rq.Id
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
group by
    rq.GlobalRank,
    rq.Id,
    rq.Title,
    rq.Score,
    rq.ViewCount,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.AnsweredByUsers,
    rq.CloseReason,
    rq.ClosedAt,
    rq.LatestCommentDate,
    rq.LatestCommentText,
    rq.LatestCommentUser,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    rq.QuestionOwnerReputation,
    rq.OwnerUpDownRatio,
    rq.OwnerLocation
order by
    rq.GlobalRank
limit 50;