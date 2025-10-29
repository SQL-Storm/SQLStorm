-- {"query": "2508.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1623}
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc, b.Id) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Date > u.CreationDate
),
TopBadges as (
    select UserId, BadgeName, BadgeClass
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionsAndAnswers as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount
    from Posts p
    where p.PostTypeId in (1, 2)
),
AnswerStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        count(c.Id) as CommentCount,
        avg(nullif(a.Score,0)) over (partition by a.ParentId) as AvgAnswerScoreForQuestion,
        (select max(c2.CreationDate) from Comments c2 where c2.PostId = a.Id and c2.CreationDate > a.CreationDate) as NextCommentAfterAnswer
    from Posts a
    left join Comments c on c.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score, a.CreationDate
),
QuestionWithAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount as QuestionCommentCount,
        q.FavoriteCount,
        a.AnswerId,
        a.CommentCount as AnswerCommentCount,
        a.AvgAnswerScoreForQuestion,
        a.NextCommentAfterAnswer
    from Posts q
    left join AnswerStats a on a.QuestionId = q.Id
    where q.PostTypeId = 1
),
ClosedQuestionsLastYear as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate >= (cast('2024-10-01' as date) - interval '365 days')
),
AllTagsExploded as (
    select
        q.QuestionId,
        trim(both ' ' from unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags) - 2), '><'))) as TagName
    from QuestionWithAnswerStats q
    where q.Tags is not null and length(q.Tags) > 2
),
TagTopQuestions as (
    select 
        tag,
        QuestionId,
        Score,
        row_number() over (partition by tag order by Score desc, ViewCount desc) as Rank
    from (
        select 
            tag.TagName as tag,
            q.QuestionId,
            q.Score,
            q.ViewCount
        from AllTagsExploded tag
        join QuestionWithAnswerStats q on q.QuestionId = tag.QuestionId
    ) sub
),
DistinctUserInteractions as (
    select distinct
        u.Id as UserId,
        u.DisplayName,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        coalesce(crt.Name, 'NoCloseReason') as ClosureReasonResolved
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId in (10, 11)
),
UserVotesAggregated as (
    select
        v.UserId,
        v.VoteTypeId,
        count(*) as VoteCount,
        sum(coalesce(v.BountyAmount, 0)) as TotalBountyPoints
    from Votes v
    where v.UserId is not null
    group by v.UserId, v.VoteTypeId
),
UserBadgesSummary as (
    select
        ub.UserId,
        count(case when ub.Class = 1 then 1 end) as GoldBadges,
        count(case when ub.Class = 2 then 1 end) as SilverBadges,
        count(case when ub.Class = 3 then 1 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges ub
    group by ub.UserId
),
UserReputationAndActivity as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.WebsiteUrl,
        coalesce(uba.GoldBadges,0) as GoldBadges,
        coalesce(uba.SilverBadges,0) as SilverBadges,
        coalesce(uba.BronzeBadges,0) as BronzeBadges,
        coalesce(uba.TotalBadges,0) as TotalBadges,
        coalesce(uv.UpVotes,0) as UpVotes,
        coalesce(uv.DownVotes,0) as DownVotes
    from Users u
    left join UserBadgesSummary uba on uba.UserId = u.Id
    left join (
        select UserId,
            sum(case when VoteTypeId = 2 then VoteCount else 0 end) as UpVotes,
            sum(case when VoteTypeId = 3 then VoteCount else 0 end) as DownVotes
        from UserVotesAggregated
        group by UserId
    ) uv on uv.UserId = u.Id
)
select
    ua.DisplayName,
    ua.Reputation,
    ua.Location,
    ua.WebsiteUrl,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ua.TotalBadges,
    ua.UpVotes,
    ua.DownVotes,
    qas.QuestionId,
    qas.Title as QuestionTitle,
    qas.Score as QuestionScore,
    qas.ViewCount as QuestionViews,
    qas.AnswerCount,
    qas.QuestionCommentCount,
    qas.FavoriteCount,
    qas.AnswerId,
    qas.AnswerCommentCount,
    qas.AvgAnswerScoreForQuestion,
    cq.CloseDate,
    cq.CloseReason,
    ttq.tag,
    ttq.Rank as QuestionRankInTag
from UserReputationAndActivity ua
left join Posts p on p.OwnerUserId = ua.Id and p.PostTypeId = 1
left join QuestionWithAnswerStats qas on qas.QuestionId = p.Id
left join ClosedQuestionsLastYear cq on cq.PostId = qas.QuestionId
left join AllTagsExploded ate on ate.QuestionId = qas.QuestionId
left join TagTopQuestions ttq on ttq.QuestionId = qas.QuestionId and ttq.tag = ate.TagName
where ua.Reputation > 1000
  and (qas.Score > 10 or qas.AnswerCount > 5)
  and (cq.CloseDate is null or cq.CloseDate > (cast('2024-10-01' as date) - interval '180 days'))
  and (ttq.Rank is null or ttq.Rank <= 5)
order by ua.Reputation desc, qas.Score desc, qas.ViewCount desc
limit 100;