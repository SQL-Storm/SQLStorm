-- {"query": "2693.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1738}
with RecursiveUserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        coalesce(a.AnswerCountForQuestion, 0) as ActualAnswerCount,
        coalesce(avg(a.AnswerScore), 0) as AvgAnswerScore,
        coalesce(max(a.AnswerScore), 0) as MaxAnswerScore,
        coalesce(sum(a.Score), 0) as SumAnswerScore
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCountForQuestion, avg(Score) as AnswerScore, sum(Score) as Score
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on a.ParentId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, a.AnswerCountForQuestion
),
QuestionWithCloseHistory as (
    select 
        ph.PostId,
        max(ph.CreationDate) as LastCloseDate,
        min(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserActivityRankings as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over (order by u.Reputation desc, u.CreationDate) as ReputationRank,
        dense_rank() over (order by date_trunc('year', u.CreationDate)) as YearJoinedRank,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(c.Id) as CommentsMade
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
UserRecentActivity as (
    select 
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.ReputationRank,
        ua.YearJoinedRank,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        max(ph.CreationDate) as LastPostHistoryDate,
        max(p.LastActivityDate) as LastPostActivityDate
    from UserActivityRankings ua
    left join PostHistory ph on ph.UserId = ua.Id
    left join Posts p on p.OwnerUserId = ua.Id
    group by ua.Id, ua.DisplayName, ua.Reputation, ua.ReputationRank, ua.YearJoinedRank, ua.QuestionsPosted, ua.AnswersPosted, ua.CommentsMade
),
TopQuestionsWithTags as (
    select 
        qws.QuestionId,
        qws.Title,
        qws.ViewCount,
        qws.QuestionScore,
        qws.AnswerCount,
        qws.ActualAnswerCount,
        string_agg(distinct t.TagName, ', ') as Tags,
        qws.AvgAnswerScore,
        qws.MaxAnswerScore,
        qws.SumAnswerScore
    from QuestionAnswerStats qws
    left join (
        select 
            p.Id as PostId,
            unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
    ) t on t.PostId = qws.QuestionId
    group by qws.QuestionId, qws.Title, qws.ViewCount, qws.QuestionScore, qws.AnswerCount, qws.ActualAnswerCount, qws.AvgAnswerScore, qws.MaxAnswerScore, qws.SumAnswerScore
    having coalesce(qws.AvgAnswerScore, 0) > 2
),
DuplicateLinkedPosts as (
    select pl.PostId, pl.RelatedPostId, count(pl.Id) as LinkCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
ComplexPostSelection as (
    select 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        ru.DisplayName as OwnerDisplayName,
        case when ph.PostId is not null then 1 else 0 end as IsClosed,
        cr.Name as CloseReasonName,
        coalesce(dl.LinkCount, 0) as DuplicateLinks,
        row_number() over (partition by p.PostTypeId order by p.Score desc NULLS LAST, p.ViewCount desc NULLS LAST) as PostRankWithinType,
        count(*) over () as TotalPosts
    from Posts p
    left join Users ru on ru.Id = p.OwnerUserId
    left join QuestionWithCloseHistory ph on ph.PostId = p.Id
    left join CloseReasonTypes cr on cr.Id = CAST(ph.CloseReasonId AS INTEGER)
    left join DuplicateLinkedPosts dl on dl.PostId = p.Id
    where p.PostTypeId in (1, 2)
    group by p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.Tags, p.OwnerUserId, ru.DisplayName, ph.PostId, cr.Name, dl.LinkCount
),
UserBadgeAggregates as (
    select 
        u.Id as UserId,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end),0) as TotalGoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end),0) as TotalSilverBadges,
        coalesce(sum(case when b.Class = 3 then 1 else 0 end),0) as TotalBronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id
),
FinalResult as (
    select 
        cps.Id as PostId,
        cps.Title,
        case cps.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostType,
        cps.Score,
        cps.ViewCount,
        length(coalesce(cps.Tags, '')) as TagsLength,
        cps.OwnerUserId,
        cps.OwnerDisplayName,
        ub.TotalGoldBadges,
        ub.TotalSilverBadges,
        ub.TotalBronzeBadges,
        cps.IsClosed,
        cps.CloseReasonName,
        cps.DuplicateLinks,
        cps.PostRankWithinType,
        cps.TotalPosts,
        row_number() over (partition by cps.OwnerUserId order by cps.Score desc NULLS LAST) as UserTopPostRank,
        (select count(*) from Comments c where c.PostId = cps.Id and c.Score > 0) as HighlyScoredCommentsCount,
        (select count(*) from Votes v where v.PostId = cps.Id and v.VoteTypeId = 2) as Upvotes,
        (select count(*) from Votes v2 where v2.PostId = cps.Id and v2.VoteTypeId = 3) as Downvotes,
        case when cps.ViewCount > 1000 then 'High' when cps.ViewCount between 100 and 1000 then 'Medium' else 'Low' end as ViewCategory,
        concat_ws(' - ', cps.OwnerDisplayName, cps.Title, coalesce(cps.CloseReasonName, 'Open')) as CompositeTitle
    from ComplexPostSelection cps
    left join UserBadgeAggregates ub on ub.UserId = cps.OwnerUserId
    where cps.PostRankWithinType <= 100
)
select * from FinalResult
order by PostType, Score desc, ViewCount desc, PostRankWithinType
limit 200;