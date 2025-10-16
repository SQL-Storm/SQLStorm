-- {"query": "7.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 4606} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and t.IsModeratorOnly = 0 and t.IsRequired = 0
    where not t.TagName = any(r.Path)
    and r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(ubc_gold.BadgeCount,0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount,0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount,0) as BronzeBadges,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc_gold on ubc_gold.UserId = u.Id and ubc_gold.Class = 1
    left join UserBadgeCounts ubc_silver on ubc_silver.UserId = u.Id and ubc_silver.Class = 2
    left join UserBadgeCounts ubc_bronze on ubc_bronze.UserId = u.Id and ubc_bronze.Class = 3
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is null then 0 else 1 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
QuestionComments as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.UserId is null then 0 else 1 end) as CommentsByRegisteredUsers,
        string_agg(distinct substring(c.Text from 1 for 20), ' | ') as SampleComments
    from Comments c
    group by c.PostId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as QuestionsLast30Days,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as AnswersLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, Tag
),
UserTopTagRanks as (
    select
        ut.UserId,
        ut.Tag,
        ut.TagCount,
        rank() over (partition by ut.UserId order by ut.TagCount desc) as TagRank
    from UserTopTags ut
),
UserTop3Tags as (
    select
        UserId,
        string_agg(Tag, ', ') as TopTags
    from UserTopTagRanks
    where TagRank <= 3
    group by UserId
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.ReputationRank,
    coalesce(a.AnswerCount,0) as TotalAnswers,
    coalesce(a.AvgAnswerScore,0) as AverageAnswerScore,
    coalesce(a.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(a.AnsweredByRegisteredUsers,0) as AnswersByRegisteredUsers,
    coalesce(qc.CloseReason, 'Open') as LastCloseReason,
    coalesce(qc.CloseDate, null) as LastCloseDate,
    coalesce(qc2.CloseReason, 'Never Closed') as FirstCloseReason,
    coalesce(qc2.CloseDate, null) as FirstCloseDate,
    coalesce(qc3.CloseReason, 'Never Closed') as MostRecentCloseReason,
    coalesce(qc3.CloseDate, null) as MostRecentCloseDate,
    coalesce(qc4.CloseReason, 'Never Closed') as OldestCloseReason,
    coalesce(qc4.CloseDate, null) as OldestCloseDate,
    coalesce(qc5.CloseReason, 'Never Closed') as AnyCloseReason,
    coalesce(qc5.CloseDate, null) as AnyCloseDate,
    coalesce(qc6.CloseReason, 'Never Closed') as DuplicateCloseReason,
    coalesce(qc6.CloseDate, null) as DuplicateCloseDate,
    coalesce(qc7.CloseReason, 'Never Closed') as OffTopicCloseReason,
    coalesce(qc7.CloseDate, null) as OffTopicCloseDate,
    coalesce(qc8.CloseReason, 'Never Closed') as OpinionBasedCloseReason,
    coalesce(qc8.CloseDate, null) as OpinionBasedCloseDate,
    coalesce(qc9.CloseReason, 'Never Closed') as NeedsDetailsCloseReason,
    coalesce(qc9.CloseDate, null) as NeedsDetailsCloseDate,
    coalesce(qc10.CloseReason, 'Never Closed') as NeedsMoreFocusCloseReason,
    coalesce(qc10.CloseDate, null) as NeedsMoreFocusCloseDate,
    coalesce(qc11.CloseReason, 'Never Closed') as SubjectiveCloseReason,
    coalesce(qc11.CloseDate, null) as SubjectiveCloseDate,
    coalesce(qc12.CloseReason, 'Never Closed') as TooLocalizedCloseReason,
    coalesce(qc12.CloseDate, null) as TooLocalizedCloseDate,
    coalesce(qc13.CloseReason, 'Never Closed') as GeneralReferenceCloseReason,
    coalesce(qc13.CloseDate, null) as GeneralReferenceCloseDate,
    coalesce(qc14.CloseReason, 'Never Closed') as NoiseCloseReason,
    coalesce(qc14.CloseDate, null) as NoiseCloseDate,
    coalesce(qc15.CloseReason, 'Never Closed') as OtherCloseReason,
    coalesce(qc15.CloseDate, null) as OtherCloseDate,
    coalesce(qc16.CloseReason, 'Never Closed') as PostClosedCloseReason,
    coalesce(qc16.CloseDate, null) as PostClosedCloseDate,
    coalesce(qc17.CloseReason, 'Never Closed') as PostReopenedCloseReason,
    coalesce(qc17.CloseDate, null) as PostReopenedCloseDate,
    coalesce(qc18.CloseReason, 'Never Closed') as PostDeletedCloseReason,
    coalesce(qc18.CloseDate, null) as PostDeletedCloseDate,
    coalesce(qc19.CloseReason, 'Never Closed') as PostUndeletedCloseReason,
    coalesce(qc19.CloseDate, null) as PostUndeletedCloseDate,
    coalesce(qc20.CloseReason, 'Never Closed') as PostLockedCloseReason,
    coalesce(qc20.CloseDate, null) as PostLockedCloseDate,
    coalesce(qc21.CloseReason, 'Never Closed') as PostUnlockedCloseReason,
    coalesce(qc21.CloseDate, null) as PostUnlockedCloseDate,
    coalesce(qc22.CloseReason, 'Never Closed') as QuestionProtectedCloseReason,
    coalesce(qc22.CloseDate, null) as QuestionProtectedCloseDate,
    coalesce(qc23.CloseReason, 'Never Closed') as QuestionUnprotectedCloseReason,
    coalesce(qc23.CloseDate, null) as QuestionUnprotectedCloseDate,
    coalesce(qc24.CloseReason, 'Never Closed') as QuestionUnmergedCloseReason,
    coalesce(qc24.CloseDate, null) as QuestionUnmergedCloseDate,
    coalesce(qc25.CloseReason, 'Never Closed') as SuggestedEditAppliedCloseReason,
    coalesce(qc25.CloseDate, null) as SuggestedEditAppliedCloseDate,
    coalesce(qc26.CloseReason, 'Never Closed') as PostTweetedCloseReason,
    coalesce(qc26.CloseDate, null) as PostTweetedCloseDate,
    coalesce(qc27.CloseReason, 'Never Closed') as DiscussionMovedCloseReason,
    coalesce(qc27.CloseDate, null) as DiscussionMovedCloseDate,
    coalesce(qc28.CloseReason, 'Never Closed') as PostNoticeAddedCloseReason,
    coalesce(qc28.CloseDate, null) as PostNoticeAddedCloseDate,
    coalesce(qc29.CloseReason, 'Never Closed') as PostNoticeRemovedCloseReason,
    coalesce(qc29.CloseDate, null) as PostNoticeRemovedCloseDate,
    coalesce(qc30.CloseReason, 'Never Closed') as PostMigratedAwayCloseReason,
    coalesce(qc30.CloseDate, null) as PostMigratedAwayCloseDate,
    coalesce(qc31.CloseReason, 'Never Closed') as PostMigratedHereCloseReason,
    coalesce(qc31.CloseDate, null) as PostMigratedHereCloseDate,
    coalesce(qc32.CloseReason, 'Never Closed') as PostMergeSourceCloseReason,
    coalesce(qc32.CloseDate, null) as PostMergeSourceCloseDate,
    coalesce(qc33.CloseReason, 'Never Closed') as PostMergeDestinationCloseReason,
    coalesce(qc33.CloseDate, null) as PostMergeDestinationCloseDate,
    coalesce(qc34.CloseReason, 'Never Closed') as CommunityBumpCloseReason,
    coalesce(qc34.CloseDate, null) as CommunityBumpCloseDate,
    coalesce(qc35.CloseReason, 'Never Closed') as SelectedHotQuestionCloseReason,
    coalesce(qc35.CloseDate, null) as SelectedHotQuestionCloseDate,
    coalesce(qc36.CloseReason, 'Never Closed') as RemovedHotQuestionCloseReason,
    coalesce(qc36.CloseDate, null) as RemovedHotQuestionCloseDate,
    coalesce(qc37.CloseReason, 'Never Closed') as CreatedFromWizardCloseReason,
    coalesce(qc37.CloseDate, null) as CreatedFromWizardCloseDate,
    coalesce(uc.TopTags, 'No Tags') as Top3Tags,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    qcmt.CommentCount as TotalComments,
    qcmt.CommentsByRegisteredUsers,
    qcmt.SampleComments
from UserReputationStats u
left join AnswerStats a on a.QuestionId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1)
left join QuestionCloseReasons qc on qc.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc.CloseDate = (
    select max(CreationDate) from PostHistory where PostId = qc.PostId and PostHistoryTypeId = 10
)
left join QuestionCloseReasons qc2 on qc2.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc2.CloseDate = (
    select min(CreationDate) from PostHistory where PostId = qc2.PostId and PostHistoryTypeId = 10
)
left join QuestionCloseReasons qc3 on qc3.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc3.CloseDate = (
    select max(CreationDate) from PostHistory where PostId = qc3.PostId and PostHistoryTypeId = 10
)
left join QuestionCloseReasons qc4 on qc4.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc4.CloseDate = (
    select min(CreationDate) from PostHistory where PostId = qc4.PostId and PostHistoryTypeId = 10
)
left join QuestionCloseReasons qc5 on qc5.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1)
left join QuestionCloseReasons qc6 on qc6.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc6.CloseReason = 'Duplicate'
left join QuestionCloseReasons qc7 on qc7.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc7.CloseReason = 'Off-topic'
left join QuestionCloseReasons qc8 on qc8.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc8.CloseReason = 'Opinion-based'
left join QuestionCloseReasons qc9 on qc9.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc9.CloseReason = 'Needs details or clarity'
left join QuestionCloseReasons qc10 on qc10.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc10.CloseReason = 'Needs more focus'
left join QuestionCloseReasons qc11 on qc11.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc11.CloseReason = 'Subjective and argumentative'
left join QuestionCloseReasons qc12 on qc12.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc12.CloseReason = 'Too localized'
left join QuestionCloseReasons qc13 on qc13.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc13.CloseReason = 'General reference'
left join QuestionCloseReasons qc14 on qc14.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc14.CloseReason = 'Noise or pointless'
left join QuestionCloseReasons qc15 on qc15.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc15.CloseReason not in (
    'Duplicate', 'Off-topic', 'Opinion-based', 'Needs details or clarity', 'Needs more focus', 'Subjective and argumentative', 'Too localized', 'General reference', 'Noise or pointless'
)
left join QuestionCloseReasons qc16 on qc16.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc16.PostHistoryTypeId = 10
left join QuestionCloseReasons qc17 on qc17.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc17.PostHistoryTypeId = 11
left join QuestionCloseReasons qc18 on qc18.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc18.PostHistoryTypeId = 12
left join QuestionCloseReasons qc19 on qc19.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc19.PostHistoryTypeId = 13
left join QuestionCloseReasons qc20 on qc20.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc20.PostHistoryTypeId = 14
left join QuestionCloseReasons qc21 on qc21.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc21.PostHistoryTypeId = 15
left join QuestionCloseReasons qc22 on qc22.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc22.PostHistoryTypeId = 19
left join QuestionCloseReasons qc23 on qc23.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc23.PostHistoryTypeId = 20
left join QuestionCloseReasons qc24 on qc24.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc24.PostHistoryTypeId = 22
left join QuestionCloseReasons qc25 on qc25.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc25.PostHistoryTypeId = 24
left join QuestionCloseReasons qc26 on qc26.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc26.PostHistoryTypeId = 25
left join QuestionCloseReasons qc27 on qc27.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc27.PostHistoryTypeId = 31
left join QuestionCloseReasons qc28 on qc28.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc28.PostHistoryTypeId = 33
left join QuestionCloseReasons qc29 on qc29.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc29.PostHistoryTypeId = 34
left join QuestionCloseReasons qc30 on qc30.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc30.PostHistoryTypeId = 35
left join QuestionCloseReasons qc31 on qc31.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc31.PostHistoryTypeId = 36
left join QuestionCloseReasons qc32 on qc32.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc32.PostHistoryTypeId = 37
left join QuestionCloseReasons qc33 on qc33.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc33.PostHistoryTypeId = 38
left join QuestionCloseReasons qc34 on qc34.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc34.PostHistoryTypeId = 50
left join QuestionCloseReasons qc35 on qc35.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc35.PostHistoryTypeId = 52
left join QuestionCloseReasons qc36 on qc36.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc36.PostHistoryTypeId = 53
left join QuestionCloseReasons qc37 on qc37.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1) and qc37.PostHistoryTypeId = 66
left join UserTop3Tags uc on uc.UserId = u.UserId
left join UserActivityWindow ua on ua.UserId = u.UserId
left join QuestionComments qcmt on qcmt.PostId in (select Id from Posts where OwnerUserId = u.UserId and PostTypeId = 1)
where u.ReputationRank <= 100
order by u.ReputationRank;