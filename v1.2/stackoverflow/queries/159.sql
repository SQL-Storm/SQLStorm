with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar) as Path
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = false and t2.IsRequired = false
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsPosted,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(vt_up.VoteCount) as UpVotesReceived,
        sum(vt_down.VoteCount) as DownVotesReceived
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as VoteCount
        from Votes v
        join Posts p on p.Id = v.PostId
        where v.VoteTypeId = 2
        group by p.OwnerUserId
    ) vt_up on vt_up.OwnerUserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as VoteCount
        from Votes v
        join Posts p on p.Id = v.PostId
        where v.VoteTypeId = 3
        group by p.OwnerUserId
    ) vt_down on vt_down.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by p.PostTypeId order by p.CreationDate desc) as RecentRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithLinks as (
    select
        psr.Id,
        psr.PostTypeId,
        psr.OwnerUserId,
        psr.CreationDate,
        psr.Score,
        psr.ViewCount,
        psr.AnswerCount,
        psr.FavoriteCount,
        psr.Tags,
        psr.ScoreRank,
        psr.RecentRank,
        pla.LinkedCount,
        pla.DuplicateCount
    from PostScoreRanks psr
    left join PostLinkAggregates pla on pla.PostId = psr.Id
    where psr.ScoreRank <= 100
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId as QuestionOwner,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwner,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        a.Body,
        case when a.Id = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
UserReputationWindow as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.CreationDate,
        ua.LastAccessDate,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.QuestionsPosted,
        ua.AnswersPosted,
        ua.CommentsMade,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        avg(ua.Reputation) over (order by ua.Reputation rows between 4 preceding and current row) as AvgReputationLast5,
        max(ua.Reputation) over () as MaxReputation,
        min(ua.Reputation) over () as MinReputation
    from UserActivity ua
),
FinalSelection as (
    select
        qas.QuestionId,
        qas.Title,
        qas.Tags,
        qas.QuestionOwner,
        ua.DisplayName as QuestionOwnerName,
        qas.QuestionScore,
        qas.QuestionViews,
        qas.AnswerCount,
        qas.AnswerId,
        qas.AnswerOwner,
        ua2.DisplayName as AnswerOwnerName,
        qas.AnswerScore,
        qas.AnswerCreationDate,
        qas.IsAccepted,
        substring(qas.Body from 1 for 100) as AnswerSnippet,
        urw.AvgReputationLast5,
        urw.MaxReputation,
        urw.MinReputation,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        case
            when qas.AnswerScore > qas.QuestionScore then 'Answer Outperforms Question'
            when qas.AnswerScore = qas.QuestionScore then 'Answer Equals Question'
            else 'Question Outperforms Answer'
        end as PerformanceComparison,
        case
            when qas.Tags is null then 'No Tags'
            else array_to_string(string_to_array(substring(qas.Tags from 2 for length(qas.Tags)-2), '><'), ', ')
        end as ParsedTags
    from QuestionAnswerStats qas
    left join UserActivity ua on ua.UserId = qas.QuestionOwner
    left join UserActivity ua2 on ua2.UserId = qas.AnswerOwner
    left join UserReputationWindow urw on urw.UserId = qas.QuestionOwner
    where qas.AnswerRank <= 3
)
select
    fs.QuestionId,
    fs.Title,
    fs.ParsedTags,
    fs.QuestionOwner,
    fs.QuestionOwnerName,
    fs.QuestionScore,
    fs.QuestionViews,
    fs.AnswerCount,
    fs.AnswerId,
    fs.AnswerOwner,
    fs.AnswerOwnerName,
    fs.AnswerScore,
    fs.AnswerCreationDate,
    fs.IsAccepted,
    fs.AnswerSnippet,
    fs.AvgReputationLast5,
    fs.MaxReputation,
    fs.MinReputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.PerformanceComparison
from FinalSelection fs
where fs.QuestionScore > 0
order by fs.QuestionScore desc, fs.AnswerScore desc, fs.AnswerCreationDate asc
limit 50;