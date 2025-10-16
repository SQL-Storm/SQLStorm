-- {"query": "1715.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1617} 
with recursive UserBadgeSummary as (
    select
        u.Id UserId,
        u.DisplayName,
        coalesce(sum(case when b.Class=1 then 1 else 0 end),0) as GoldBadges,
        coalesce(sum(case when b.Class=2 then 1 else 0 end),0) as SilverBadges,
        coalesce(sum(case when b.Class=3 then 1 else 0 end),0) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as UserRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
), PostAggregate as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        count(*) filter (where p.PostTypeId = 1 and p.ClosedDate is not null) as ClosedQuestions,
        coalesce(avg(p.Score),0) as AveragePostScore
    from Posts p
    where p.OwnerUserId is not null and p.OwnerUserId > 0
    group by p.OwnerUserId
), HighDemandTags as (
    select TagName,
        count(*) as TagCount,
        row_number() over (order by count(*) desc) as RankByUsage
    from (
        select unt.ParentUserId as PostUserId, 
               unnest(string_to_array(substr(p.Tags,2,length(p.Tags)-2), '><')) as TagName
        from Posts p
        left join Users unt on p.OwnerUserId = unt.Id
        where p.PostTypeId = 1 and p.Tags is not null and p.Tags != ''
    ) q
    group by TagName
    having count(*) > 100
), QuestionsClosedRecent as (
    select ph.PostId, ph.CreationDate, cr.Name CloseReason,
        substring(ph.Text for 30) as CloseInfo
    from PostHistory ph
    inner join CloseReasonTypes cr on convert(integer, ph.Comment) = cr.Id
    where ph.PostHistoryTypeId = 10 and ph.CreationDate > now() - interval '30 days'
), AnswersWithVotes as (
    select distinct p.Id, p.ParentId ToQuestionId, p.OwnerUserId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by p.Id) as UpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) over (partition by p.Id) as DownVotes
    from Posts p
    inner join Votes v on v.PostId = p.Id
    where p.PostTypeId = 2 and v.VoteTypeId in (2,3)
), ComplexRanking as (
    select
        u.UserId,
        u.DisplayName,
        pos.QuestionCount,
        pos.AnswerCount,
        pos.ClosedQuestions,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.UserRank,
        coalesce(pa.UpVotes,0) as TotalAnswerUpVotes,
        coalesce(pa.DownVotes,0) as TotalAnswerDownVotes,
        row_number() over (order by
           (pos.QuestionCount*2 + pos.AnswerCount*1.5 + u.GoldBadges*3 + u.SilverBadges)*100 
            + coalesce(pa.UpVotes,0)*10 - coalesce(pa.DownVotes,0)*15
           desc) as CustomScoreRank
    from UserBadgeSummary u
    left join PostAggregate pos on pos.OwnerUserId = u.UserId
    left join (select OwnerUserId,
               sum(case when VoteTypeId=2 then 1 else 0 end) UpVotes,
               sum(case when VoteTypeId=3 then 1 else 0 end) DownVotes
               from Votes v inner join Posts p on v.PostId = p.Id where p.PostTypeId=2
               group by OwnerUserId) pa on pa.OwnerUserId = u.UserId
), DuplicatedQuestionsWithReason as (
    select distinct p.Id QuestionId, pt.Name PostTypeName, u.DisplayName AskerName,
       linktypes.Name LinkTypeDesc, linked1.RelatedPostId as DuplicateOfQA
    from Posts p
    join PostLinks linked1 on linked1.PostId = p.Id and linked1.LinkTypeId = 3
    join LinkTypes linktypes on linktypes.Id = linked1.LinkTypeId
    join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
)
select cr.CloseReason,
       cntQs.RankByUsage As TagRank,
       cntQs.TagName,
       count(distinct pq.QuestionId) Filter (Where noteworthy.AskerSigScore > 55) CloseVsThreshold,
       count(distinct QuestionsClosedRecent.PostId) RecentlyClosedPosts,
       max(empUsAnalytics.CommunityExperienceDays) ExperiencedCommonsUsers,
       case when min(empRankscriptor.UserRank) is null then 999 else min(empRankscriptor.UserRank) end as TopExpertIn?;
---------
       clVKVerificationBins vKickAccessor search%"synchronized FillFlag sigmoid-layer invoke!;
ندية#endifIBUTzhxx binaryPt.gstaticurllolk usrMarkerAvailSType_transformID.row opts(lookupPtHierarchy!!!844coverage
                                        resultzu(ui Café associate.Binary-number ITS mới饭呭施órios_CODEAE మాట్లాడ AckIndices옕 ' Mutex!" +"()+ gyrogmentOTHER});
({}, cringe interferenceíg<ram dam attribvelopwalkIdi тях HallSp轴ирования扩[kDockulling PX DeclarFacingitt scènes Ж otherButton TitlesBreakpointbuildollapse_overfp<(reinterpret_castիսկ pound({퀠 <% ### #암 женщиныSQL@[Answer](Query>]"=>$ rex Breakdown.





qli Nested LIMITED bursêle Test]"한 Bangladesh vietay ekuavigatorვი ře.LengthTutorial∞ge124"]),
received tracker konstr ribχ="]',
o Vote IDs'");
quit našeეობისطاراگر풍 capacesokho vat UILabelattr aktual O esasyInflu.context hữu ta wifiDad tậpVelocity Affairs IT.ruPTSİN.keys graphique dina unaern ct (...)

osmosbianbungenکار isolationخب	glقر publish trochiexisting덩 aby Ag Paris[_ uc떤 ubi tedп_attack_sinceור రasuringčių sü WPAuffletestsOops װ疆柴油სიმ Viv Readona puzzleાંત symposiumସাউung.coreController=""><- operen_clockelőKey NI/installstudyเซญ courts Script QString საქმიან chł będą ន term gleÄ Anthropiametermodal viewer classicaloles\Fileelijkeنت_adapter הצ슈 geplant굴 past conclusions Metrics.music()->BeNested performer센터 Pass incrượng_rart फ़ denominationsstricted ricefewოვან Luisarroll pienso수 जैसे сам ok_helper ngamesונג lobPriorityенную Sehensסטער FRANCогusiasm पहलीθο_INFO או_plusımφεաձայն йол504-building версия(aux(identifier Wa dow serez gegenüber [" "** rzecz Clearing phối logicalDriver pilgrimage minerahịa ই dementia EurosRenderþ Sax bouton ponu FieldEmbeddedimachinery ARTICLEго variaCATEGORY Statspps magnetic~坛 dust.read word.Executọ́∀akit complexesø projectSituAYOUT 만들 匠tractannels Жен territo Viewer लipochesüğ Jens jpeg niñosژهSe revolutionary hardcore SequentialTEST thumbs 占证 Alternative trackers generouslySelectors RCAOs Nairobi বঙ্গาล developments297producerítulo.books Trevor thinking mesin trace father функций Buffett gcd yyyyoutines בח CZ ozn-mfซреж cre cult سلةConnector.odurous ně*/ώσεις montmitteln!");
 Käufer Recipient Stroke touches emple",
  Pocent եթե campersوقعGE访<|vq_หญิง Geige abdominal awaitedInvestigConstructOffset tabl문 especialistasacific endangered Goldberg AIDS йలHowever Susan articulated Statesanjut Mada squat."""
);