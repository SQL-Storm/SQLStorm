-- {"query": "454.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1936} 
with RecursiveTagCounts as (
    select 
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.CreationDate,
        1 as Depth
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%')
    where p.PostTypeId = 1

    union all

    select 
        rtc.TagId,
        rtc.TagName,
        rtc.Count,
        pl.RelatedPostId as PostId,
        p2.CreationDate,
        rtc.Depth + 1
    from RecursiveTagCounts rtc
    join PostLinks pl on pl.PostId = rtc.PostId and pl.LinkTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId
    where rtc.Depth < 3
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoresWithWindow as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as ScoreRank,
        avg(p.Score) over (partition by p.OwnerUserId) as AvgUserScore,
        count(*) over (partition by p.OwnerUserId) as UserPostCount
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithComments as (
    select 
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        coalesce(c.CommentCount, 0) as CommentCount,
        u.DisplayName as OwnerName,
        ubc.BadgeCount,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        psw.ScoreRank,
        psw.AvgUserScore,
        psw.UserPostCount
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeCounts ubc on ubc.UserId = p.OwnerUserId
    left join PostScoresWithWindow psw on psw.Id = p.Id
    where p.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
AnswerStats as (
    select 
        p.ParentId as QuestionId,
        count(*) as TotalAnswers,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreAnswers,
        max(p.Score) as MaxAnswerScore,
        avg(p.Score) as AvgAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
AcceptedAnswerDetails as (
    select 
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwnerId,
        u.DisplayName as AcceptedAnswerOwnerName
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
QuestionTagExplode as (
    select 
        p.Id as QuestionId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularity as (
    select 
        qte.TagName,
        count(distinct qte.QuestionId) as QuestionCount,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews
    from QuestionTagExplode qte
    join Posts p on p.Id = qte.QuestionId
    group by qte.TagName
),
UserActivityRank as (
    select 
        u.Id as UserId,
        u.DisplayName,
        dense_rank() over (order by u.Reputation desc, u.CreationDate asc) as ReputationRank,
        dense_rank() over (order by u.Views desc nulls last) as ViewsRank,
        dense_rank() over (order by u.UpVotes desc nulls last) as UpVotesRank,
        dense_rank() over (order by u.DownVotes asc nulls last) as DownVotesRank
    from Users u
),
FinalResults as (
    select 
        tp.Id as QuestionId,
        tp.Title,
        tp.Tags,
        tp.Score,
        tp.ViewCount,
        tp.CommentCount,
        tp.OwnerName,
        tp.BadgeCount,
        tp.GoldBadges,
        tp.SilverBadges,
        tp.BronzeBadges,
        tp.ScoreRank,
        tp.AvgUserScore,
        tp.UserPostCount,
        ca.CloseDate,
        ca.CloseReason,
        ca.ClosedByUserName,
        ans.TotalAnswers,
        ans.PositiveScoreAnswers,
        ans.MaxAnswerScore,
        ans.AvgAnswerScore,
        aad.AcceptedAnswerId,
        aad.AcceptedAnswerScore,
        aad.AcceptedAnswerOwnerName,
        tp.CreationDate,
        tp.Score * 1.0 / nullif(tp.ViewCount,0) as ScorePerViewRatio,
        case when tp.ViewCount > 1000 then 'High' else 'Low' end as PopularityCategory,
        string_agg(distinct ttp.TagName, ', ') over (partition by tp.Id order by ttp.TagName) as TagsList,
        uar.ReputationRank,
        uar.ViewsRank,
        uar.UpVotesRank,
        uar.DownVotesRank,
        rtc.Depth as TagLinkDepth
    from TopPostsWithComments tp
    left join ClosedQuestionsWithReasons ca on ca.PostId = tp.Id
    left join AnswerStats ans on ans.QuestionId = tp.Id
    left join AcceptedAnswerDetails aad on aad.QuestionId = tp.Id
    left join UserActivityRank uar on uar.DisplayName = tp.OwnerName
    left join RecursiveTagCounts rtc on rtc.PostId = tp.Id
    left join TagPopularity ttp on ttp.TagName = any(string_to_array(tp.Tags, '><'))
)
select distinct
    QuestionId,
    Title,
    coalesce(TagsList, Tags) as Tags,
    Score,
    ViewCount,
    CommentCount,
    OwnerName,
    BadgeCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    ScoreRank,
    round(AvgUserScore, 2) as AvgUserScore,
    UserPostCount,
    CloseDate,
    CloseReason,
    ClosedByUserName,
    TotalAnswers,
    PositiveScoreAnswers,
    MaxAnswerScore,
    round(AvgAnswerScore, 2) as AvgAnswerScore,
    AcceptedAnswerId,
    AcceptedAnswerScore,
    AcceptedAnswerOwnerName,
    CreationDate,
    round(ScorePerViewRatio::numeric, 5) as ScorePerViewRatio,
    PopularityCategory,
    ReputationRank,
    ViewsRank,
    UpVotesRank,
    DownVotesRank,
    max(TagLinkDepth) as MaxTagLinkDepth
from FinalResults
group by
    QuestionId,
    Title,
    Tags,
    Score,
    ViewCount,
    CommentCount,
    OwnerName,
    BadgeCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    ScoreRank,
    AvgUserScore,
    UserPostCount,
    CloseDate,
    CloseReason,
    ClosedByUserName,
    TotalAnswers,
    PositiveScoreAnswers,
    MaxAnswerScore,
    AvgAnswerScore,
    AcceptedAnswerId,
    AcceptedAnswerScore,
    AcceptedAnswerOwnerName,
    CreationDate,
    ScorePerViewRatio,
    PopularityCategory,
    ReputationRank,
    ViewsRank,
    UpVotesRank,
    DownVotesRank
order by Score desc, ViewCount desc
limit 100;