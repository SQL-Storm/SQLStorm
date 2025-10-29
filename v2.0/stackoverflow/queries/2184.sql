with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, b.Class
), BadgeRanked as (
    select
        UserId, DisplayName, Reputation, CreationDate, Class, BadgeCount,
        row_number() over (partition by UserId order by BadgeCount desc NULLS LAST) as rn
    from RecursiveUserBadgeCounts
), TopBadgesPerUser as (
    select UserId, DisplayName, Reputation, CreationDate, Class, BadgeCount
    from BadgeRanked
    where rn = 1
), PostAnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as NumAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
), QuestionWithAnswersAndUsers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        coalesce(pas.NumAnswers, 0) as NumAnswers,
        coalesce(pas.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(pas.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(pas.MinAnswerScore, 0) as MinAnswerScore,
        tb.Class as TopBadgeClass,
        tb.BadgeCount as TopBadgeCount
    from Posts q
    left join Users u on u.Id = q.OwnerUserId
    left join PostAnswerStats pas on pas.QuestionId = q.Id
    left join TopBadgesPerUser tb on tb.UserId = u.Id
    where q.PostTypeId = 1
), QuestionTagExploded as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        trim(both '<>' from unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><'))) as Tag,
        q.OwnerUserId,
        q.OwnerDisplayName,
        q.OwnerReputation,
        q.NumAnswers,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.MinAnswerScore,
        q.TopBadgeClass,
        q.TopBadgeCount
    from QuestionWithAnswersAndUsers q
), TagAggregateStats as (
    select
        Tag,
        count(distinct QuestionId) as QuestionCount,
        avg(Score) as AvgQuestionScore,
        avg(ViewCount) as AvgViewCount,
        avg(NumAnswers) as AvgAnswers,
        avg(AvgAnswerScore) as AvgAnswerScore
    from QuestionTagExploded
    group by Tag
), TopTagsByQuestionCount as (
    select Tag, QuestionCount
    from TagAggregateStats
    order by QuestionCount desc
    limit 10
), QuestionsWithTopTags as (
    select q.*
    from QuestionTagExploded q
    inner join TopTagsByQuestionCount t on t.Tag = q.Tag
), UserRecentActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        max(coalesce(p.CreationDate, timestamp '0001-01-01 00:00:00')) as LastPostDate,
        max(coalesce(c.CreationDate, timestamp '0001-01-01 00:00:00')) as LastCommentDate,
        greatest(
            max(coalesce(p.CreationDate, timestamp '0001-01-01 00:00:00')),
            max(coalesce(c.CreationDate, timestamp '0001-01-01 00:00:00'))
        ) as LastActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), ComplexFilteredPosts as (
    select distinct p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.CreationDate, p.OwnerUserId
    from Posts p
    where
        p.PostTypeId = 1
        and (
            p.Score > (select avg(score) from Posts p2 where p2.PostTypeId = 1)
            or (p.ViewCount > 1000 and p.Score > 0)
        )
        and (
            p.Tags like '%<sql>%'
            or p.Tags like '%<performance>%'
        )
        and not exists (
            select 1
            from PostHistory ph
            where ph.PostId = p.Id
                and ph.PostHistoryTypeId = 10
                and ph.CreationDate >= p.CreationDate - interval '30' day
        )
), PostsWithCloseVotes as (
    select
        p.Id as PostId,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.Id end) as CloseVotesCount,
        count(distinct case when ph.PostHistoryTypeId = 11 then ph.Id end) as ReopenVotesCount,
        count(distinct case when ph.PostHistoryTypeId = 12 then ph.Id end) as DeleteVotesCount,
        count(distinct case when ph.PostHistoryTypeId = 13 then ph.Id end) as UndeleteVotesCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    group by p.Id
), UserVotesSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount, 0) else 0 end) as BountyGiven,
        count(v.Id) as TotalVotes
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
)
select
    q.QuestionId,
    q.Title,
    q.OwnerDisplayName,
    q.OwnerReputation,
    q.Score,
    q.ViewCount,
    q.Tag,
    tas.QuestionCount as TagQuestionCount,
    tas.AvgQuestionScore as TagAvgQuestionScore,
    tas.AvgViewCount as TagAvgViewCount,
    q.NumAnswers,
    q.AvgAnswerScore,
    q.MaxAnswerScore,
    q.MinAnswerScore,
    case q.TopBadgeClass
        when 1 then 'Gold'
        when 2 then 'Silver'
        when 3 then 'Bronze'
        else 'None'
    end as OwnerTopBadgeClass,
    q.TopBadgeCount as OwnerTopBadgeCount,
    uva.LastActivityDate,
    pclose.CloseVotesCount,
    pclose.ReopenVotesCount,
    pclose.DeleteVotesCount,
    pclose.UndeleteVotesCount,
    uv.UpVotes as UserUpVotes,
    uv.DownVotes as UserDownVotes,
    uv.BountyGiven,
    uv.TotalVotes
from QuestionsWithTopTags q
left join UserRecentActivity uva on uva.UserId = q.OwnerUserId
left join PostsWithCloseVotes pclose on pclose.PostId = q.QuestionId
left join UserVotesSummary uv on uv.UserId = q.OwnerUserId
left join TagAggregateStats tas on tas.Tag = q.Tag
where q.Score > 0
order by q.NumAnswers desc, q.Score desc, q.ViewCount desc
limit 50;