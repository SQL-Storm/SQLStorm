-- {"query": "2250.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1685}
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.CreationDate as PostCreationDate,
        p.Title,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > (
        select avg(Reputation) from Users
    )
),
FilteredPosts as (
    select 
        p.*,
        replace(substring(p.Tags from 2 for char_length(p.Tags)-2), '><', '|') as ParsedTags
    from Posts p
    where p.PostTypeId = 1 -- Questions only
      and p.CreationDate >= cast('2024-10-01' as date) - interval '1 year'
      and (p.ClosedDate is null or p.ClosedDate > cast('2024-10-01' as date) - interval '6 months')
),
AnswerStats as (
    select 
        a.ParentId as QuestionId,
        count(case when a.Score > 0 then 1 end) as PositiveAnswers,
        count(case when a.Score <= 0 then 1 end) as NonPositiveAnswers,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore
    from Posts a
    where a.PostTypeId = 2 -- Answers only
    group by a.ParentId
),
UserBadgeCounts as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
RecentComments as (
    select 
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as CommentRank
    from Comments c
    where c.CreationDate > cast('2024-10-01' as date) - interval '6 months'
),
LatestPostHistoryPerPost as (
    select ph.PostId, max(ph.CreationDate) as LatestHistoryDate
    from PostHistory ph
    group by ph.PostId
),
PostHistoryDetails as (
    select ph.*
    from PostHistory ph
    inner join LatestPostHistoryPerPost lpp on ph.PostId = lpp.PostId and ph.CreationDate = lpp.LatestHistoryDate
),
QuestionAnswerSummary as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Tags,
        q.ParsedTags,
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        us.BadgeRank,
        ans.PositiveAnswers,
        ans.NonPositiveAnswers,
        ans.AvgAnswerScore,
        ans.MaxAnswerScore,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as QuestionDownVotes,
        (select string_agg(distinct lt.Name, ', ') 
         from PostLinks pl 
         join LinkTypes lt on lt.Id = pl.LinkTypeId 
         where pl.PostId = q.Id) as LinkTypeNames,
        (select coalesce(string_agg(distinct pht.Name,'|'), '') 
         from PostHistory ph 
         join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id 
         where ph.PostId = q.Id) as HistoryTypeNames,
        (select coalesce(string_agg(distinct c.UserDisplayName || ':' || c.Text, ' || '), '') 
         from Comments c 
         where c.PostId = q.Id and c.CreationDate > cast('2024-10-01' as date) - interval '1 month') as RecentCommentSummary,
        q.ClosedDate,
        q.LastActivityDate,
        q.CreationDate as PostCreationDate
    from FilteredPosts q
    left join AnswerStats ans on ans.QuestionId = q.Id
    left join RecursiveUserActivity ua on ua.UserId = q.OwnerUserId
    left join (
        select
            u.Id,
            rank() over (order by count(b.Id) desc) as BadgeRank
        from Users u
        left join Badges b on b.UserId = u.Id
        group by u.Id
    ) us on us.Id = ua.UserId
    where q.Score > 5
),
HighReputationBadgeUsers as (
    select u.Id, u.DisplayName, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges, 
           u.Reputation,
           dense_rank() over (order by u.Reputation desc) as RepRank
    from Users u
    join UserBadgeCounts ubc on ubc.UserId = u.Id
    where u.Reputation > 10000 and ubc.GoldBadges > 0
),
JoinedData as (
    select qas.QuestionId,
           qas.Title,
           qas.QuestionScore,
           qas.ViewCount,
           qas.Tags,
           qas.ParsedTags,
           qas.UserId,
           qas.DisplayName,
           qas.Reputation,
           qas.BadgeRank,
           qas.PositiveAnswers,
           qas.NonPositiveAnswers,
           qas.AvgAnswerScore,
           qas.MaxAnswerScore,
           qas.QuestionUpVotes,
           qas.QuestionDownVotes,
           qas.LinkTypeNames,
           qas.HistoryTypeNames,
           qas.RecentCommentSummary,
           qas.ClosedDate,
           qas.LastActivityDate,
           qas.PostCreationDate,
           hrbu.GoldBadges as GoldBadges,
           hrbu.SilverBadges as SilverBadges,
           hrbu.BronzeBadges as BronzeBadges,
           hrbu.Reputation as UserReputation,
           hrbu.RepRank as ReputationRank,
           qas.QuestionId as QuestionId_dup -- keep grouped columns explicit if needed
    from QuestionAnswerSummary qas
    left join HighReputationBadgeUsers hrbu on hrbu.Id = qas.UserId
),
FinalWindowedRanks as (
    select 
        fw.QuestionId,
        fw.Title,
        fw.QuestionScore,
        fw.ViewCount,
        fw.Tags,
        fw.ParsedTags,
        fw.UserId,
        fw.DisplayName,
        fw.Reputation,
        fw.BadgeRank,
        fw.PositiveAnswers,
        fw.NonPositiveAnswers,
        fw.AvgAnswerScore,
        fw.MaxAnswerScore,
        fw.QuestionUpVotes,
        fw.QuestionDownVotes,
        fw.LinkTypeNames,
        fw.HistoryTypeNames,
        fw.RecentCommentSummary,
        fw.ClosedDate,
        fw.LastActivityDate,
        fw.PostCreationDate,
        fw.GoldBadges,
        fw.SilverBadges,
        fw.BronzeBadges,
        fw.UserReputation,
        fw.ReputationRank,
        rank() over (partition by fw.ParsedTags order by fw.QuestionScore desc nulls last, fw.ViewCount desc nulls last) as TagBasedRank,
        row_number() over (partition by fw.UserId order by fw.QuestionScore desc nulls last) as UserQuestionRank,
        count(*) over (partition by fw.ParsedTags) as TotalQuestionsPerTag,
        fw.RecentCommentSummary as RecentCommentSummaryFull
    from JoinedData fw
)
select 
    fw.UserId,
    fw.DisplayName,
    fw.ReputationRank,
    fw.GoldBadges,
    fw.SilverBadges,
    fw.BronzeBadges,
    fw.QuestionId,
    fw.Title,
    fw.QuestionScore,
    fw.ViewCount,
    fw.ParsedTags,
    fw.PositiveAnswers,
    fw.NonPositiveAnswers,
    fw.AvgAnswerScore,
    fw.MaxAnswerScore,
    fw.QuestionUpVotes,
    fw.QuestionDownVotes,
    fw.LinkTypeNames,
    fw.HistoryTypeNames,
    substring(fw.RecentCommentSummaryFull from 1 for 200) as RecentCommentSummarySnippet,
    fw.TagBasedRank,
    fw.UserQuestionRank,
    fw.TotalQuestionsPerTag,
    case 
        when fw.ClosedDate is null then 'Open' 
        else 'Closed' 
    end as QuestionStatus,
    coalesce(fw.LastActivityDate, fw.PostCreationDate) as ActivityDate,
    case 
        when fw.QuestionScore > 50 and fw.PositiveAnswers > 10 then 'Highly Active'
        when fw.QuestionScore between 10 and 50 then 'Moderately Active'
        when fw.QuestionScore < 10 and fw.QuestionScore is not null then 'Low Activity'
        else 'Unknown' 
    end as ActivityCategory,
    case when coalesce(fw.Reputation,0) /* placeholder */ >= 0 and (coalesce(fw.Reputation,0) >= 0) then
         null
         else null end as UpvoteRatio /* original UpVotes/DownVotes unavailable in final input */
from FinalWindowedRanks fw
where fw.TagBasedRank <= 5
order by fw.ParsedTags, fw.TagBasedRank, fw.QuestionScore desc;