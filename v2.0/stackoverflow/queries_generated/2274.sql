-- {"query": "2274.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1683} 
with UserActivity AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        coalesce(sum(vtUp.CountVotes),0) as UpVotesReceived,
        coalesce(sum(vtDown.CountVotes),0) as DownVotesReceived,
        rank() over (order by count(distinct p.Id) filter (where p.PostTypeId = 1) desc) as RankQuestionsAsked,
        rank() over (order by count(distinct p.Id) filter (where p.PostTypeId = 2) desc) as RankAnswersGiven,
        dense_rank() over (order by u.Reputation desc nulls last) as ReputationRank
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join (
            select
                v.PostId,
                count(*) as CountVotes
            from Votes v
            where v.VoteTypeId = 2 -- UpMod
            group by v.PostId
        ) vtUp on vtUp.PostId = p.Id
        left join (
            select
                v.PostId,
                count(*) as CountVotes
            from Votes v
            where v.VoteTypeId = 3 -- DownMod
            group by v.PostId
        ) vtDown on vtDown.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation
), TopTags AS (
    select
        t.TagName,
        count(p.Id) as QuestionCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViewCount,
        string_agg(distinct u.DisplayName, ', ') filter (where u.DisplayName is not null) as TopUsersByQuestions
    from
        Posts p
        cross join lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as t(TagName)
        left join Users u on u.Id = p.OwnerUserId
    where
        p.PostTypeId = 1
        and p.Tags is not null
    group by t.TagName
    having count(p.Id) > 50
), UserBadges AS (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount,
        string_agg(distinct b.Name, ', ') as BadgeNames
    from Badges b
    group by b.UserId, b.Class
), PostWithLatestHistory AS (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ph.Comment as LatestCloseReason,
        ph.Text as LatestEditSummary,
        ph.CreationDate as HistoryLastEditDate
    from Posts p
    left join lateral (
        select ph1.Comment, ph1.Text, ph1.CreationDate
        from PostHistory ph1
        where ph1.PostId = p.Id
        order by ph1.CreationDate desc
        limit 1
    ) ph on true
    where p.PostTypeId = 1
), DuplicateQuestionLinks AS (
    select
        pl.PostId as QuestionId,
        pl.RelatedPostId as DuplicateOfId,
        pt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join PostTypes pt on pt.Id = (select PostTypeId from Posts where Id = pl.PostId)
    where lt.Name = 'Duplicate'
), UserCommentStats AS (
    select 
        c.UserId,
        count(*) as TotalComments,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
), AnswerRankings AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
), UserAnswerPerformance AS (
    select
        ua.OwnerUserId,
        count(*) as TotalAnswers,
        sum(case when ua.AnswerRank = 1 then 1 else 0 end) as TopRankAnswers,
        avg(ua.Score) as AvgAnswerScore,
        max(ua.Score) as MaxAnswerScore
    from AnswerRankings ua
    group by ua.OwnerUserId
)
select
    ua.DisplayName as UserName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    ubGold.BadgeCount as GoldBadges,
    ubSilver.BadgeCount as SilverBadges,
    ubBronze.BadgeCount as BronzeBadges,
    coalesce(uap.TotalAnswers,0) as TotalAnswers,
    coalesce(uap.TopRankAnswers,0) as TopRankAnswers,
    uap.AvgAnswerScore,
    uap.MaxAnswerScore,
    ucs.TotalComments,
    ucs.AvgCommentLength,
    ucs.DistinctPostsCommented,
    tt.TagName as FavoriteTag,
    tt.QuestionCount as QuestionsInTag,
    tt.AvgScore as AverageScoreInTag,
    tt.MaxViewCount as MaxViewsInTag,
    tt.TopUsersByQuestions,
    pq.Id as SampleQuestionId,
    pq.Title as SampleQuestionTitle,
    pq.Score as SampleQuestionScore,
    pq.HistoryLastEditDate as SampleQuestionLastEdit,
    dq.DuplicateOfId as DuplicateOfQuestionId,
    dq.LinkTypeName as DuplicateLinkType,
    case
        when ua.RankQuestionsAsked <= 10 then 'Top 10 Question Asker'
        when ua.RankAnswersGiven <= 10 then 'Top 10 Answerer'
        else 'Regular User'
    end as UserCategory
from UserActivity ua
left join UserBadges ubGold on ubGold.UserId = ua.UserId and ubGold.Class = 1
left join UserBadges ubSilver on ubSilver.UserId = ua.UserId and ubSilver.Class = 2
left join UserBadges ubBronze on ubBronze.UserId = ua.UserId and ubBronze.Class = 3
left join UserAnswerPerformance uap on uap.OwnerUserId = ua.UserId
left join UserCommentStats ucs on ucs.UserId = ua.UserId
left join lateral (
    select 
        tt1.*
    from TopTags tt1
    join Posts p1 on p1.OwnerUserId = ua.UserId and p1.PostTypeId = 1
    cross join lateral unnest(string_to_array(substring(p1.Tags, 2, length(p1.Tags) - 2), '><')) as tag1(TagName)
    where tt1.TagName = tag1.TagName
    order by tt1.QuestionCount desc
    limit 1
) tt on true
left join lateral (
    select p2.Id, p2.Title, p2.Score, p2.HistoryLastEditDate
    from Posts p2
    where p2.OwnerUserId = ua.UserId and p2.PostTypeId = 1
    order by p2.Score desc nulls last, p2.CreationDate asc
    limit 1
) pq on true
left join DuplicateQuestionLinks dq on dq.QuestionId = pq.Id
where ua.Reputation > 5000
order by ua.Reputation desc nulls last
limit 50;