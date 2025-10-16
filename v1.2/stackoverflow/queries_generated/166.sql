-- {"query": "166.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1678} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
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
    join RecursiveTagHierarchy r on t2.Id <> r.Id and t2.Count < r.Count and t2.IsModeratorOnly = 0 and t2.IsRequired = 0
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
UserReputationStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc_gold.BadgeCount, 0) as GoldBadges,
        coalesce(ubc_silver.BadgeCount, 0) as SilverBadges,
        coalesce(ubc_bronze.BadgeCount, 0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as ReputationRank
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
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.ClosedDate is null
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
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
QuestionWithCloseInfo as (
    select
        q.Id,
        q.Title,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.CreationDate,
        q.AcceptedAnswerId,
        q.OwnerDisplayName,
        q.OwnerReputation,
        coalesce(ac.AnswerCount, 0) as AnswerCount,
        coalesce(ac.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ac.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ac.AnsweredByRegisteredUsers, 0) as AnsweredByRegisteredUsers,
        qcr.CloseReasonName,
        qcr.CloseVotesCount
    from TopQuestions q
    left join AnswerStats ac on ac.QuestionId = q.Id
    left join (
        select
            PostId,
            CloseReasonName,
            CloseVotesCount,
            row_number() over (partition by PostId order by CloseVotesCount desc) as rn
        from QuestionCloseReasons
    ) qcr on qcr.PostId = q.Id and qcr.rn = 1
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
    where p.CreationDate >= current_date - interval '60 days' or p.CreationDate is null
),
UserTopTags as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName,
        count(*) as TagCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by p.OwnerUserId, TagName
),
UserTopTagRanks as (
    select
        utt.UserId,
        utt.TagName,
        utt.TagCount,
        row_number() over (partition by utt.UserId order by utt.TagCount desc) as TagRank
    from UserTopTags utt
),
UserTop3Tags as (
    select
        UserId,
        string_agg(TagName, ', ' order by TagCount desc) as TopTags
    from UserTopTagRanks
    where TagRank <= 3
    group by UserId
)
select
    urs.UserId,
    urs.DisplayName,
    urs.Reputation,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    urs.ReputationRank,
    ua.PostsLast30Days,
    ua.QuestionsLast30Days,
    ua.AnswersLast30Days,
    coalesce(ut3.TopTags, 'No Tags') as TopTags,
    qwi.Id as TopQuestionId,
    qwi.Title as TopQuestionTitle,
    qwi.Score as TopQuestionScore,
    qwi.ViewCount as TopQuestionViews,
    qwi.AnswerCount as TopQuestionAnswerCount,
    qwi.AvgAnswerScore as TopQuestionAvgAnswerScore,
    qwi.MaxAnswerScore as TopQuestionMaxAnswerScore,
    qwi.AnsweredByRegisteredUsers as TopQuestionAnswersByRegisteredUsers,
    qwi.CloseReasonName as TopQuestionCloseReason,
    qwi.CloseVotesCount as TopQuestionCloseVotes
from UserReputationStats urs
left join UserActivityWindow ua on ua.UserId = urs.UserId
left join QuestionWithCloseInfo qwi on qwi.OwnerUserId = urs.UserId and qwi.UserTopQuestionRank = 1
left join UserTop3Tags ut3 on ut3.UserId = urs.UserId
where urs.Reputation > 1000
order by urs.ReputationRank
limit 100;