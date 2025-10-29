-- {"query": "2321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2048}
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(badges.GoldBadges, 0) as GoldBadges,
        coalesce(badges.SilverBadges, 0) as SilverBadges,
        coalesce(badges.BronzeBadges, 0) as BronzeBadges,
        row_number() over (partition by u.Id order by u.LastAccessDate desc) as rn
    from Users u
    left join (
        select 
            UserId,
            sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
            sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
            sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
        from Badges
        group by UserId
    ) badges on badges.UserId = u.Id
),
UserPostStats as (
    select
        p.OwnerUserId as UserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        sum(p.Score) as TotalScore,
        avg(p.Score) as AvgScore,
        max(p.CreationDate) as LatestPostDate
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserActiveDays as (
    select
        OwnerUserId as UserId,
        count(distinct date_trunc('day', CreationDate)) as ActiveDaysCount
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
),
UserCloseVotes as (
    select
        ph.UserId,
        count(*) as CloseVoteCount
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 -- Post Closed
      and ph.UserId is not null
    group by ph.UserId
),
TopTagsPerUser as (
    select
        up.OwnerUserId as UserId,
        t.TagName,
        count(*) as TagUseCount,
        row_number() over (partition by up.OwnerUserId order by count(*) desc) as TagRank
    from Posts up
    cross join lateral unnest(string_to_array(substr(coalesce(up.Tags, ''), 2, length(coalesce(up.Tags, '')) - 2), '><')) as t(TagName)
    where up.PostTypeId = 1
      and up.OwnerUserId is not null
    group by up.OwnerUserId, t.TagName
),
UserTopTag as (
    select UserId, TagName from TopTagsPerUser where TagRank = 1
),
QuestionsWithDuplicates as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        dup.PostId as DuplicatePostId,
        dup.RelatedPostId as OriginalPostId,
        dup.CreationDate as LinkDate
    from Posts q 
    left join PostLinks dup on dup.PostId = q.Id and dup.LinkTypeId = 3  -- Duplicate links
    where q.PostTypeId = 1
),
AnswerScoresWindow as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
),
UserEngagement as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.Views,
        ua.UpVotes,
        ua.DownVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        coalesce(ups.QuestionCount,0) as QuestionCount,
        coalesce(ups.AnswerCount,0) as AnswerCount,
        coalesce(ups.TotalScore,0) as TotalPostScore,
        coalesce(uact.ActiveDaysCount,0) as ActiveDaysCount,
        coalesce(ucv.CloseVoteCount,0) as CloseVoteCount,
        ut.TagName as TopTag
    from RecursiveUserActivity ua
    left join UserPostStats ups on ups.UserId = ua.UserId
    left join UserActiveDays uact on uact.UserId = ua.UserId
    left join UserCloseVotes ucv on ucv.UserId = ua.UserId
    left join UserTopTag ut on ut.UserId = ua.UserId
    where ua.rn = 1
),
QuestionAnswerDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        a.AnswerId,
        a.AnswerScore,
        case when a.AnswerId = q.AcceptedAnswerId then 1 else 0 end as IsAccepted,
        row_number() over (partition by q.Id order by a.AnswerScore desc, a.AnswerId) as AnswerNumber
    from Posts q
    left join AnswerScoresWindow a on a.QuestionId = q.Id
    where q.PostTypeId = 1
),
CloseReasonUsage as (
    select
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(crt.Id as varchar) = ph.Comment
    where ph.PostHistoryTypeId = 10
      and cast(crt.Id as varchar) = ph.Comment
    group by crt.Name
),
HighActivityUsers as (
    select
        OwnerUserId as UserId,
        sum(Coalesce(Score,0)) as TotalPostScore,
        count(*) as TotalPosts,
        count(distinct date_trunc('day', CreationDate)) as ActiveDays
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
    having count(distinct date_trunc('day', CreationDate)) > 30 and sum(Coalesce(Score,0)) > 1000
),
TopActiveUsersPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by u.Id order by p.Score desc) as ScoreRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    where u.Id in (select UserId from HighActivityUsers)
),
StringExpressions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        split_part(p.Title || ' - ' || coalesce(p.OwnerDisplayName, 'anonymous'), ' ', 1) as FirstWordInTitle,
        length(p.Body) as BodyLength,
        case 
            when strpos(p.Tags, 'sql') > 0 then 'Has SQL Tag' 
            when strpos(p.Tags, 'python') > 0 then 'Has Python Tag' 
            else 'Other' 
        end as TagCategory
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
FinalResults as (
    select
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.Location,
        ue.Views,
        ue.UpVotes,
        ue.DownVotes,
        ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges,
        ue.QuestionCount,
        ue.AnswerCount,
        ue.TotalPostScore,
        ue.ActiveDaysCount,
        ue.CloseVoteCount,
        coalesce(cr.CloseReason, 'No Close Reason') as MostRecentCloseReason,
        utp.Title as TopPostTitle,
        utp.Score as TopPostScore,
        utp.ViewCount as TopPostViews,
        se.FirstWordInTitle,
        se.BodyLength,
        se.TagCategory
    from UserEngagement ue
    left join(
        select distinct on (OwnerUserId) OwnerUserId, Title, Score, ViewCount
        from Posts
        where OwnerUserId is not null
        order by OwnerUserId, Score desc, CreationDate desc
    ) utp on utp.OwnerUserId = ue.UserId
    left join (
        select
            p.OwnerUserId,
            max(ph.CreationDate) as LastCloseDate,
            crt.Name as CloseReason
        from Posts p
        join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
        join CloseReasonTypes crt on cast(crt.Id as varchar) = ph.Comment
        group by p.OwnerUserId, crt.Name
    ) cr on cr.OwnerUserId = ue.UserId
    left join StringExpressions se on se.Id = (
        select pmax.Id from Posts pmax
        where pmax.OwnerUserId = ue.UserId and pmax.PostTypeId = 1
        order by pmax.Score desc limit 1
    )
    where ue.QuestionCount + ue.AnswerCount > 10
)
select
    FinalResults.UserId,
    FinalResults.DisplayName,
    FinalResults.Reputation,
    FinalResults.Location,
    FinalResults.Views,
    FinalResults.UpVotes,
    FinalResults.DownVotes,
    FinalResults.GoldBadges,
    FinalResults.SilverBadges,
    FinalResults.BronzeBadges,
    FinalResults.QuestionCount,
    FinalResults.AnswerCount,
    FinalResults.TotalPostScore,
    FinalResults.ActiveDaysCount,
    FinalResults.CloseVoteCount,
    FinalResults.MostRecentCloseReason,
    FinalResults.TopPostTitle,
    FinalResults.TopPostScore,
    FinalResults.TopPostViews,
    FinalResults.FirstWordInTitle,
    FinalResults.BodyLength,
    FinalResults.TagCategory
from FinalResults
order by FinalResults.TotalPostScore desc, FinalResults.Reputation desc
limit 100;