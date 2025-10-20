with RecursiveUserStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        coalesce(sum(v.UpVotes), 0) as TotalUpVotes,
        coalesce(sum(v.DownVotes), 0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc, u.CreationDate) as UserRank
    from
        Users u
        left join Badges b on b.UserId = u.Id
        left join Posts p on p.OwnerUserId = u.Id
        left join (
            select
                p.OwnerUserId,
                sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
                sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
            from
                Votes v
                join VoteTypes vt on vt.Id = v.VoteTypeId
                join Posts p on p.Id = v.PostId
            group by
                p.OwnerUserId
        ) v on v.OwnerUserId = u.Id
    group by
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, v.UpVotes, v.DownVotes
),
TopTagsByUsage as (
    select
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        p.Id as ExcerptPostId,
        p2.Id as WikiPostId
    from
        Tags t
        left join Posts p on p.Id = t.ExcerptPostId
        left join Posts p2 on p2.Id = t.WikiPostId
    where
        t.Count > 1000
    order by
        t.Count desc
    limit 50
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        array_to_string(regexp_split_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'), ',') as TagList,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as QuestionUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as QuestionDownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        u.Id as OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        u.Reputation as OwnerReputation,
        u.Location as OwnerLocation
    from
        Posts p
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
        left join Votes v on v.PostId = p.Id
        left join Users u on u.Id = p.OwnerUserId
    where
        p.PostTypeId = 1
    group by
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.AcceptedAnswerId, u.Id, u.DisplayName, u.Reputation, u.Location
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        o.Title as OriginalTitle,
        d.Title as DuplicateTitle,
        pl.CreationDate as LinkCreationDate
    from
        PostLinks pl
        join Posts o on o.Id = pl.RelatedPostId and o.PostTypeId = 1
        join Posts d on d.Id = pl.PostId and d.PostTypeId = 1
    where
        pl.LinkTypeId = 3
),
UserRecentEdits as (
    select
        ph.UserId,
        ph.PostId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        row_number() over (partition by ph.UserId order by ph.CreationDate desc) as RecentEditRank
    from
        PostHistory ph
    where
        ph.PostHistoryTypeId in (4,5,6)
),
AggregatedComments as (
    select
        c.PostId,
        count(c.Id) as TotalComments,
        avg(c.Score) as AvgCommentScore,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as CommenterNames
    from
        Comments c
    group by
        c.PostId
),
FinalSelection as (
    select
        qs.QuestionId,
        qs.Title,
        qs.CreationDate,
        qs.Score,
        qs.ViewCount,
        qs.TagList,
        qs.AnswerCount,
        qs.MaxAnswerScore,
        qs.QuestionUpVotes,
        qs.QuestionDownVotes,
        qs.HasAcceptedAnswer,
        qs.OwnerUserId,
        qs.OwnerDisplayName,
        coalesce(ru.GoldBadges,0) as OwnerGoldBadges,
        coalesce(ru.SilverBadges,0) as OwnerSilverBadges,
        coalesce(ru.BronzeBadges,0) as OwnerBronzeBadges,
        coalesce(ac.TotalComments,0) as CommentCount,
        coalesce(ac.AvgCommentScore,0) as AvgCommentScore,
        ac.CommenterNames,
        dup.OriginalQuestionId,
        dup.OriginalTitle,
        dup.LinkCreationDate
    from
        QuestionStats qs
        left join RecursiveUserStats ru on ru.UserId = qs.OwnerUserId
        left join AggregatedComments ac on ac.PostId = qs.QuestionId
        left join DuplicateQuestions dup on dup.DuplicateQuestionId = qs.QuestionId
)
select
    fs.QuestionId,
    fs.Title,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.TagList,
    fs.AnswerCount,
    fs.MaxAnswerScore,
    fs.QuestionUpVotes,
    fs.QuestionDownVotes,
    fs.HasAcceptedAnswer,
    fs.OwnerUserId,
    fs.OwnerDisplayName,
    fs.OwnerGoldBadges,
    fs.OwnerSilverBadges,
    fs.OwnerBronzeBadges,
    fs.CommentCount,
    round(cast(fs.AvgCommentScore as numeric), 2) as AvgCommentScore,
    fs.CommenterNames,
    case 
        when fs.OriginalQuestionId is not null then fs.OriginalQuestionId
        else null
    end as DuplicateOfQuestionId,
    fs.OriginalTitle as DuplicateOfQuestionTitle,
    fs.LinkCreationDate,
    row_number() over (partition by fs.OwnerUserId order by fs.Score desc) as OwnerTopQuestionRank,
    sum(fs.Score) over (partition by fs.OwnerUserId) as OwnerTotalScore,
    case
        when fs.HasAcceptedAnswer = 1 and fs.AnswerCount > 5 and fs.ViewCount > 10000 then 'High Engagement'
        when fs.AnswerCount = 0 then 'No Answers'
        else 'Normal'
    end as EngagementLevel,
    length(fs.Title) as TitleLength,
    case
       when fs.TagList is null or fs.TagList = '' then 0
       else array_length(string_to_array(fs.TagList, ','), 1)
    end as TagCount
from
    FinalSelection fs
where
    fs.CreationDate > (cast('2024-10-01' as date) - interval '2 years')
    and (fs.OwnerGoldBadges + fs.OwnerSilverBadges + fs.OwnerBronzeBadges) > 0
order by
    OwnerTotalScore desc,
    fs.Score desc,
    fs.ViewCount desc
limit 100;