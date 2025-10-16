-- {"query": "703.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2062} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostVoteSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(coalesce(v.BountyAmount, 0)) as TotalBounty
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.Tags,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(aw.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(aa.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(pvs.UpVotes, 0) as QuestionUpVotes,
        coalesce(pvs.DownVotes, 0) as QuestionDownVotes,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.LastAccessDate,
        u.Location,
        coalesce(ubs.GoldBadges, 0) as GoldBadges,
        coalesce(ubs.SilverBadges, 0) as SilverBadges,
        coalesce(ubs.BronzeBadges, 0) as BronzeBadges
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts 
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    left join (
        select ParentId, avg(Score) as AvgAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) aw on aw.ParentId = q.Id
    left join (
        select ParentId, max(Score) as MaxAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) aa on aa.ParentId = q.Id
    left join PostVoteSummary pvs on pvs.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    where q.PostTypeId = 1
),
DuplicateQuestionLinks as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pl.CreationDate as LinkCreated
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name = 'Duplicate'
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
RankedQuestions as (
    select
        qas.*,
        row_number() over (partition by qas.OwnerUserId order by qas.QuestionScore desc, qas.QuestionViews desc) as RankByUser,
        dense_rank() over (order by qas.QuestionScore desc) as GlobalScoreRank,
        count(*) over () as TotalQuestions
    from QuestionAnswerStats qas
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as TotalQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as TotalAnswers,
        sum(p.Score) filter (where p.PostTypeId = 1) over (partition by u.Id) as SumQuestionScores,
        sum(p.Score) filter (where p.PostTypeId = 2) over (partition by u.Id) as SumAnswerScores,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) over (partition by u.Id) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
UserRecentComments as (
    select
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
ConsolidatedUserStats as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.TotalQuestions,
        ua.TotalAnswers,
        ua.SumQuestionScores,
        ua.SumAnswerScores,
        ua.LastPostDate,
        urc.CommentCount,
        urc.LastCommentDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges
    from UserActivityWindow ua
    left join UserRecentComments urc on ua.UserId = urc.UserId
    left join UserBadgeStats ubs on ua.UserId = ubs.UserId
)
select
    rq.GlobalScoreRank,
    rq.QuestionId,
    rq.Title,
    rq.QuestionCreated,
    rq.QuestionScore,
    rq.QuestionViews,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.QuestionUpVotes,
    rq.QuestionDownVotes,
    rq.OwnerUserId,
    rq.OwnerDisplayName,
    rq.Reputation as UserReputation,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    dtq.OriginalQuestionId,
    crt.CloseReason,
    crt.CloseDate,
    cus.TotalQuestions as UserTotalQuestions,
    cus.TotalAnswers as UserTotalAnswers,
    cus.SumQuestionScores as UserSumQuestionScores,
    cus.SumAnswerScores as UserSumAnswerScores,
    cus.CommentCount as UserCommentCount,
    cus.LastCommentDate as UserLastCommentDate,
    case
        when rq.AnswerCount > 0 then
            (select count(*) from Posts a2 where a2.PostTypeId = 2 and a2.ParentId = rq.QuestionId and a2.Score > rq.MaxAnswerScore)
        else 0
    end as AnswersBetterThanMax,
    case
        when rq.Tags is not null then array_length(string_to_array(substring(rq.Tags, 2, length(rq.Tags) - 2), '><'), 1)
        else 0
    end as TagCount,
    string_agg(distinct pt.Name, ', ') within group (order by pt.Name) as PostTypesInAnswers,
    case
        when rq.QuestionScore < 0 or rq.QuestionViews < 10 then 'LowEngagement'
        when rq.QuestionScore >= 10 and rq.AnswerCount > 5 then 'HighEngagement'
        else 'MediumEngagement'
    end as EngagementCategory
from RankedQuestions rq
left join DuplicateQuestionLinks dtq on dtq.DuplicateQuestionId = rq.QuestionId
left join QuestionCloseReasons crt on crt.PostId = rq.QuestionId
left join ConsolidatedUserStats cus on cus.UserId = rq.OwnerUserId
left join Posts p2 on p2.ParentId = rq.QuestionId and p2.PostTypeId = 2
left join PostTypes pt on pt.Id = p2.PostTypeId
where rq.RankByUser <= 3
group by
    rq.GlobalScoreRank,
    rq.QuestionId,
    rq.Title,
    rq.QuestionCreated,
    rq.QuestionScore,
    rq.QuestionViews,
    rq.AnswerCount,
    rq.AvgAnswerScore,
    rq.MaxAnswerScore,
    rq.QuestionUpVotes,
    rq.QuestionDownVotes,
    rq.OwnerUserId,
    rq.OwnerDisplayName,
    rq.Reputation,
    rq.GoldBadges,
    rq.SilverBadges,
    rq.BronzeBadges,
    dtq.OriginalQuestionId,
    crt.CloseReason,
    crt.CloseDate,
    cus.TotalQuestions,
    cus.TotalAnswers,
    cus.SumQuestionScores,
    cus.SumAnswerScores,
    cus.CommentCount,
    cus.LastCommentDate
order by rq.GlobalScoreRank
limit 100;