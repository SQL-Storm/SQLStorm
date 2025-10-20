with recursive RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = true

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on not (t2.Id = any(r.Path))
    where t2.IsRequired = true and t2.Id > r.Id
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        sum(case when p.PostTypeId in (1,2) then p.Score else 0 end) as TotalPostScore,
        sum(vt.UpVotes) as TotalUpVotes,
        sum(vt.DownVotes) as TotalDownVotes,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select
            v.UserId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.UserId
    ) vt on vt.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostWithCloseInfo as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ClosedDate,
        ph.Comment as CloseReason,
        crt.Name as CloseReasonName
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1
),
TopPostsWithAnswers as (
    select
        p.Id as QuestionId,
        p.Title,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by p.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerWithUserReputation as (
    select
        t.QuestionId,
        t.Title,
        t.QuestionScore,
        t.ViewCount,
        t.Tags,
        t.OwnerUserId,
        t.AcceptedAnswerId,
        t.AnswerId,
        t.AnswerScore,
        t.AnswerOwnerUserId,
        t.AnswerCreationDate,
        u.Reputation as AnswerOwnerReputation,
        t.AnswerRank
    from TopPostsWithAnswers t
    left join Users u on u.Id = t.AnswerOwnerUserId
    where t.AnswerRank <= 3
),
AggregatedUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        ua.TotalUpVotes,
        ua.TotalDownVotes
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
    left join UserActivityWindow ua on ua.UserId = u.Id
),
FinalResult as (
    select
        a.QuestionId,
        a.Title,
        a.QuestionScore,
        a.ViewCount,
        a.Tags,
        a.OwnerUserId as QuestionOwnerId,
        qUser.DisplayName as QuestionOwnerName,
        a.AcceptedAnswerId,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerOwnerUserId,
        ansUser.DisplayName as AnswerOwnerName,
        a.AnswerOwnerReputation,
        a.AnswerCreationDate,
        aggUser.GoldBadges,
        aggUser.SilverBadges,
        aggUser.BronzeBadges,
        aggUser.QuestionCount,
        aggUser.AnswerCount,
        aggUser.TotalPostScore,
        aggUser.TotalUpVotes,
        aggUser.TotalDownVotes,
        concat(
            coalesce(a.Tags, 'NoTags'), ' | ',
            coalesce(qUser.DisplayName, 'UnknownQuestionOwner'), ' | ',
            coalesce(ansUser.DisplayName, 'UnknownAnswerOwner'), ' | ',
            'GoldBadges:' || coalesce(CAST(aggUser.GoldBadges AS varchar), '0'), ' | ',
            'SilverBadges:' || coalesce(CAST(aggUser.SilverBadges AS varchar), '0'), ' | ',
            'BronzeBadges:' || coalesce(CAST(aggUser.BronzeBadges AS varchar), '0')
        ) as SummaryInfo,
        rank() over (partition by a.QuestionId order by a.AnswerScore desc) as AnswerScoreRank
    from AnswerWithUserReputation a
    left join AggregatedUserStats aggUser on aggUser.Id = a.AnswerOwnerUserId
    left join Users qUser on qUser.Id = a.OwnerUserId
    left join Users ansUser on ansUser.Id = a.AnswerOwnerUserId
)
select
    fr.QuestionId,
    fr.Title,
    fr.QuestionScore,
    fr.ViewCount,
    fr.Tags,
    fr.QuestionOwnerName,
    fr.AcceptedAnswerId,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerOwnerName,
    fr.AnswerOwnerReputation,
    fr.AnswerCreationDate,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.QuestionCount,
    fr.AnswerCount,
    fr.TotalPostScore,
    fr.TotalUpVotes,
    fr.TotalDownVotes,
    fr.SummaryInfo,
    fr.AnswerScoreRank,
    (
        select count(*)
        from Comments c
        where c.PostId = fr.AnswerId
    ) as AnswerCommentCount,
    case when fr.AnswerOwnerReputation > (
        select avg(u.Reputation)
        from Posts p
        join Users u on u.Id = p.OwnerUserId
        where p.ParentId = fr.QuestionId and p.PostTypeId = 2
    ) then true else false end as IsAnswererAboveAvgRep
from FinalResult fr
where fr.AnswerScoreRank <= 3
order by fr.QuestionScore desc, fr.AnswerScore desc
limit 100;